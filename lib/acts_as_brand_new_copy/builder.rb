require 'json'
require 'acts_as_brand_new_copy/merge'
require 'acts_as_brand_new_copy/standard'

module ActsAsBrandNewCopy
  class Builder
    def initialize(serialized_hash)
      @hash_origin  = serialized_hash
      @hash_copy    = JSON.parse(serialized_hash.to_json) # a way to do deep clone
      @save_order   = calculate_save_order
      @instances    = extract_instances
      @queue        = prepare_copy_queue
      @full_context = {
        :save_order => @save_order,
        :save_queue => @queue,
        :instances  => @instances
      }
    end

    def invoke_callback(callbacks)
      invoke_callback_recursively([@hash_origin], callbacks)
    end

    def save
      @queue.each_pair do |klass_name, hash_copy_array|
        next if hash_copy_array.blank?

        # belongs_to
        hash_copy_array.each{ |hash_copy| update_key_on_self_table(klass_name, hash_copy) }

        # AN OPTIMIZED APPROACH IS TO BATCH INSERT THE SAME LEVEL
        # BUT NOTE CURRENT IMPLEMENTATION ONLY HANDLED MYSQL SYNTAX
        batch_insert_copy(klass_name.constantize, hash_copy_array)

        # has_one, has_many and has_and_belongs_to_many
        hash_copy_array.each{ |hash_copy| update_key_on_association_tables(klass_name, hash_copy) }
      end
    end

    def all_saved_instances
      @instances.values
    end

    def new_id(klass_name, old_id)
      copy_object = find_object_by_old_id(klass_name, old_id)
      return nil if copy_object.nil?
      if copy_object['id'] == copy_object['id_before_copy']
        raise 'copy object not saved to db!'
      end
      copy_object['id']
    end

    private

    def invoke_callback_recursively(hash_origin_array, callbacks)
      hash_origin_array.each do |hash_origin|
        callbacks.each do |callback|
          if callback.is_a?(Symbol)
            invoke_single_callback(callback, hash_origin)
          else
            child_association = callback.keys.first
            child_callbacks   = callback.values.first
            invoke_callback_recursively(
              hash_child(hash_origin, child_association),
              child_callbacks
            )
          end
        end
      end
    end

    def invoke_single_callback(callback, hash_origin)
      hash_klass = hash_origin['klass'].constantize
      hash_copy = find_object_by_old_id(hash_origin['klass'], hash_origin['id_before_copy'])
      unless hash_klass.send(callback, hash_origin, hash_copy, @full_context)
        raise "run callback '#{callback}' failed on #{Standard.object_hash_to_s(hash_origin)}"
      end
    end

    def hash_child(hash_origin, association)
      hash_klass = hash_origin['klass'].constantize
      name       = Standard.association_klass_name(hash_klass, association)
      hash_origin['associations'][name]
    end

    def calculate_save_order
      constraints, klasses = Set.new, Set.new
      traverse do |current_hash|
        klasses.add(current_hash['klass']) unless klasses.include?(current_hash['klass'])

        current_hash['dependencies'].each_pair do |_, aso_dependencies|
          aso_dependencies.each do |aso_dependency|
            aso_dependency['save_order_constraints'].each do |constraint_string|
              front, back = constraint_string.split('_')
              klasses.add(front) unless klasses.include?(front)
              klasses.add(back) unless klasses.include?(back)
              # same active record class
              unless front == back || constraints.include?(constraint_string)
                constraints.add(constraint_string)
              end
            end
          end
        end
      end

      # construct an order which can ensure all constraints are met
      valid_save_order = klasses.to_a.sort
      has_modifications = true
      while has_modifications
        has_modifications = false
        constraints.each do |constraint|
          front, back = constraint.split('_')
          front_index = valid_save_order.index(front)
          back_index = valid_save_order.index(back)
          if front_index > back_index
            valid_save_order[back_index], valid_save_order[front_index] = front, back
            has_modifications = true
          end
        end
      end
      valid_save_order
    end

    # breadth first
    def traverse(&block)
      not_visit = [@hash_copy]
      while (not_visit.size > 0)
        current_hash = not_visit.shift
        yield current_hash
        current_hash['associations'].each_pair do |_, aso_hash_array|
          aso_hash_array.each{ |aso_hash| not_visit << aso_hash }
        end
      end
    end

    def extract_instances
      unique_instances = {}
      traverse do |current_hash|
        key = Standard.object_key(current_hash['klass'], current_hash['id'])
        if unique_instances.key?(key)
          unique_instances[key] = merge_associations_dependencies(unique_instances[key], current_hash)
        else
          unique_instances[key] = current_hash
        end
      end
      unique_instances
    end

    def merge_associations_dependencies(hash, another_hash)
      dup = hash.reject { |k, _| ['associations', 'dependencies'].include?(k) }
      dup['associations'] = Merge.deep_merge(hash['associations'], another_hash['associations'])
      dup['dependencies'] = Merge.deep_merge(hash['dependencies'], another_hash['dependencies'])
      dup
    end

    def prepare_copy_queue
      queue = ActiveSupport::OrderedHash.new
      @save_order.each{ |item| queue[item] = [] }
      @instances.each_pair{ |_, hash| queue[hash['klass']] << hash }
      queue
    end

    def update_key_on_self_table(klass_name, hash_copy)
      hash_copy['dependencies'].each_pair do |aso_name, aso_dependencies|
        aso_dependencies.each do |aso_dependency|
          if aso_dependency['key_position'] == 'self_table'
            foreign_key = aso_dependency['association_key_on_self_table']
            update_object_by_old_id(klass_name, hash_copy['id'], {
              foreign_key => new_id(aso_name, hash_copy[foreign_key])
            })
          end
        end
      end
    end

    def update_key_on_association_tables(klass_name, hash_copy)
      hash_copy['dependencies'].each_pair do |aso_name, aso_dependencies|
        aso_dependencies.each do |aso_dependency|
          if aso_dependency['key_position'] == 'association_table'
            aso_foreign_key = aso_dependency['self_key_on_association_table']
            hash_copy['associations'][aso_name].each do |instance|
              update_object_by_old_id(aso_name, instance['id'], {
                aso_foreign_key => new_id(klass_name, instance[aso_foreign_key])
              })
            end
          elsif aso_dependency['key_position'] == 'join_table'
            foreign_key_to_self = aso_dependency['self_key_on_join_table']
            foreign_key_to_association = aso_dependency['association_key_on_join_table']
            join_table_instances = hash_copy['associations'][aso_dependency['join_table_class']]
            join_table_instances.each do |instance|
              update_object_by_old_id(aso_dependency['join_table_class'], instance['id'], {
                foreign_key_to_self        => new_id(klass_name, instance[foreign_key_to_self]),
                foreign_key_to_association => new_id(aso_name, instance[foreign_key_to_association])
              })
            end
          end
        end
      end
    end

    def do_insert(klass, columns, hash_copies)
      connection = klass.connection
      value_list = hash_copies.map do |hash_copy|
        quoted_copy_values = columns.map do |column|
          case column.name
          when 'updated_at', 'created_at'
            'NOW()'
          else
            connection.quote(hash_copy[column.name], column)
          end
        end
        "(#{quoted_copy_values.join(', ')})"
      end
      column_list = columns.map do |column|
        connection.quote_column_name(column.name)
      end
      result = connection.execute("INSERT INTO #{connection.quote_table_name(klass.table_name)} (#{column_list.join(', ')}) VALUES #{value_list.join(', ')}")
      connection.last_inserted_id(result)
    end

    def batch_insert_copy_auto_generate_ids(klass, hash_copy_slice)
      columns = klass.columns.reject { |k, _| 'id' == k.name }
      last_id = do_insert(klass, columns, hash_copy_slice)
      first_id = last_id - hash_copy_slice.size + 1
      hash_copy_slice.each_with_index{ |hash_copy, index| hash_copy['id'] = first_id + index }
    end

    def batch_insert_copy(klass, hash_copy_array)
      # in case of array too large
      hash_copy_array.each_slice(50) do |hash_copy_slice|
        batch_insert_copy_auto_generate_ids(klass, hash_copy_slice)
      end
    end

    def find_object_by_old_id(klass_name, old_id)
      @instances[Standard.object_key(klass_name, old_id)]
    end

    def update_object_by_old_id(klass_name, old_id, new_attributes)
      copy_object = find_object_by_old_id(klass_name, old_id)
      new_attributes.each_pair do |key, value|
        copy_object[key] = value
      end
      if copy_object['id'] != copy_object['id_before_copy']
        # object already saved, this may happens when the same level copies has dependencies
        update_inserted_copy(copy_object['klass'].constantize, copy_object['id'], new_attributes)
      end
    end

    def update_inserted_copy(klass, id, new_attributes)
      sub_conditions = []
      new_attributes.each_pair do |key, value|
        sub_conditions << "#{key}=#{value}"
      end
      klass.connection.execute("UPDATE #{klass.table_name} SET #{sub_conditions.join(',')} WHERE id=#{id}")
    end
  end
end
