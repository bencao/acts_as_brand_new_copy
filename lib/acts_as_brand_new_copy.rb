require "acts_as_brand_new_copy/version"

module ActsAsBrandNewCopy
  extend ActiveSupport::Concern

  class BrandNewCopyBuilder

    def initialize(hash_origin, hash_copy)
      @hash_origin  = hash_origin
      @hash_copy    = hash_copy
      @save_order   = calculate_save_order
      @instances    = extract_instances
      @queue        = prepare_copy_queue
      @full_context = {
        :root_hash_origin => @hash_origin,
        :root_hash_copy   => @hash_copy,
        :save_order       => @save_order,
        :save_queue       => @queue,
        :instances        => @instances
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
        # BUT NOTE CURRENT IMPLEMENTATION IS IS FOR MYSQL ONLY
        batch_insert_copy(klass_name.constantize, hash_copy_array)

        # has_one, has_many and has_and_belongs_to_many
        hash_copy_array.each{ |hash_copy| update_key_on_association_tables(klass_name, hash_copy) }
      end
    end

    def all_saved_instances
      @instances.values
    end

    private

    def invoke_callback_recursively(hash_origin_array, callbacks)
      raise 'callbacks option must be an array' unless callbacks.is_a?(Array)

      hash_origin_array.each_with_index do |hash_origin, index|
        raise 'hash_origin must be an hash' unless hash_origin.is_a?(Hash)

        hash_klass = hash_origin['klass'].constantize

        callbacks.each do |callback|
          if callback.is_a?(Symbol)
            unless hash_klass.send(callback, hash_origin, find_object_by_old_id(hash_origin['klass'], hash_origin['id_before_copy']), @full_context)
              raise "run #{callback} callback failed, " +
                " hash_origin=#{find_object_by_old_id(hash_origin['klass'], hash_origin['id_before_copy'])}"
            end
          elsif callback.is_a?(Hash)
            path, path_callbacks = hash_klass.reflect_on_association(callback.keys.first).class_name, callback.values.first
            invoke_callback_recursively(hash_partial_by_path(hash_origin, [path]), path_callbacks)
          else
            raise 'the callback param value must be a symbol or hash'
          end
        end
      end
    end

    def hash_partial_by_path(hash, path)
      path_dup = path.dup
      hash_partial = hash
      hash_partial = hash_partial['associations'][path_dup.shift] while path_dup.present?
      hash_partial
    end

    def calculate_save_order
      constraints, klasses = Set.new, Set.new
      traverse do |current_hash|
        klasses.add(current_hash['klass']) unless klasses.include?(current_hash['klass'])

        current_hash['dependencies'].each_pair do |aso_name, aso_dependencies|
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
        current_hash['associations'].each_pair do |aso_name, aso_hash_array|
          aso_hash_array.each{ |aso_hash| not_visit << aso_hash }
        end
      end
    end

    def extract_instances
      unique_instances = {}
      traverse do |current_hash|
        key = object_key(current_hash['klass'], current_hash['id'])
        if unique_instances.has_key?(key)
          unique_instances[key] = merge_associations_dependencies_for_copy(unique_instances[key], current_hash)
        else
          unique_instances[key] = current_hash
        end
      end
      unique_instances
    end

    def merge_associations_dependencies_for_copy(hash, another_hash)
      dup = hash.reject{ |k, v| ['associations', 'dependencies'].include?(k) }

      dup['associations'] = {}
      (hash['associations'].keys + another_hash['associations'].keys).each do |aso_name|
        dup['associations'][aso_name] = (hash['associations'][aso_name] || []) + (another_hash['associations'][aso_name] || [])
      end

      dup['dependencies'] = {}
      (hash['dependencies'].keys + another_hash['dependencies'].keys).each do |aso_name|
        dup['dependencies'][aso_name] = (hash['dependencies'][aso_name] || []) + (another_hash['dependencies'][aso_name] || [])
      end

      dup
    end

    def prepare_copy_queue
      queue = ActiveSupport::OrderedHash.new
      @save_order.each{ |item| queue[item] = [] }
      @instances.each_pair{ |key, hash| queue[hash['klass']] << hash }
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
      columns = klass.columns.reject {|k, v| 'id' == k.name}
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

    def self.object_key(klass, id)
      absolute_klass_name = klass.start_with?("::") ? "#{klass}" : "::#{klass}"
      absolute_klass_name.constantize.table_name + "_#{id}"
    end

    def object_key(klass, id)
      self.class.object_key(klass, id)
    end

    def find_object_by_old_id(klass_name, old_id)
      @instances[object_key(klass_name, old_id)]
    end

    def new_id(klass_name, old_id)
      copy_object = find_object_by_old_id(klass_name, old_id)
      return nil if copy_object.nil?
      raise 'copy object not saved to db!' if copy_object['id'] == copy_object['id_before_copy']
      copy_object['id']
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

  module ClassMethods
    def brand_new_copy_object_key(klass, id)
      BrandNewCopyBuilder.object_key(klass, id)
    end

    def brand_new_copy_guess_join_table_class(join_table_name)
      final_name = [join_table_name.singularize, join_table_name.pluralize].detect do |possible_name|
        Object.const_defined?(possible_name.camelize)
      end
      if final_name
        final_name.camelize
      else
        raise "Do not support has_and_belongs_to_many associations" +
          "that can not guess join table class from join table name"
      end
    end
  end

  def quoted_attributes_for_copy
    quoted_attributes = {}
    attributes.each_pair do |key, value|
      case value.class.to_s
      when "Date", "Time", "ActiveSupport::TimeWithZone"
        quoted_attributes[key] = connection.quoted_date(value)
      when "BigDecimal"
        quoted_attributes[key] = value.to_s("F")
      else
        quoted_attributes[key] = value
      end
    end
    # in case the table has no id
    unless quoted_attributes.has_key?('id')
      quoted_attributes['id'] = quoted_attributes.values.join('_')
    end
    quoted_attributes['id_before_copy'] = quoted_attributes['id']
    quoted_attributes['klass'] = self.class.to_s
    quoted_attributes
  end

  # sample associations = [:billing_term_condition, {:line_items => [:targeting_criteria]}, :resource_user_assignments]
  def serialize_hash_for_copy(associations=nil)
    associations = [] if associations.nil?
    raise "associations param (#{associations}) must be inside an array" unless associations.is_a?(Array)

    result = quoted_attributes_for_copy.merge({
      'associations'   => {},
      'dependencies'   => {}
    })

    associations.uniq.each do |association|
      if association.is_a?(Symbol)
        aso_name_underscore, aso_instances, aso_option = association.to_s, self.send(association), nil
      elsif association.is_a?(Hash)
        aso_name_underscore, aso_instances, aso_option = association.keys.first.to_s, self.send(association.keys.first), association.values.first
      else
        raise 'association param value must be a symbol or hash'
      end

      reflection = self.class.reflect_on_association(aso_name_underscore.to_sym)
      unless result['dependencies'].has_key?(reflection.class_name)
        result['dependencies'][reflection.class_name] = []
      end
      result['dependencies'][reflection.class_name] << resolve_copy_dependencies(reflection)

      unless result['associations'].has_key?(reflection.class_name)
        result['associations'][reflection.class_name] = if aso_instances.is_a?(Array)
          aso_instances.map{ |ass| ass.serialize_hash_for_copy(aso_option) }
        else
          aso_instances.present? ? [aso_instances.serialize_hash_for_copy(aso_option)] : []
        end
      end

      # has_and_belongs_to_many and has_one(through), has_many(through) may introduce an implicit association
      implicit_association_class, implicit_association_hash = implicit_join_table_association(reflection)
      if implicit_association_class.present? && (not result['associations'].has_key?(implicit_association_class))
        result['associations'][implicit_association_class] = implicit_association_hash
      end
    end
    result
  end

  def resolve_copy_dependencies(reflection)
    self_class = reflection.active_record.to_s
    association_class = reflection.class_name
    if (reflection.through_reflection.present?)
      join_table_class = reflection.through_reflection.class_name
      # has_one through OR has_many through
      {
        'key_position'                  => 'join_table',
        'save_order_constraints'        => [
          "#{self_class}_#{join_table_class}",
          "#{association_class}_#{join_table_class}",
          "#{association_class}_#{self_class}"
        ],
        'join_table_class'              => join_table_class,
        'self_key_on_join_table'        => reflection.through_reflection.foreign_key,
        'association_key_on_join_table' => reflection.source_reflection.foreign_key
      }
    else
      case (reflection.macro)
      when :has_and_belongs_to_many
        join_table_class = self.class.brand_new_copy_guess_join_table_class(reflection.options[:join_table])
        {
          'key_position'                  => 'join_table',
          'save_order_constraints'        => [
            "#{self_class}_#{join_table_class}",
            "#{association_class}_#{join_table_class}",
            "#{association_class}_#{self_class}"
          ],
          'join_table_class'              => join_table_class,
          'self_key_on_join_table'        => reflection.foreign_key,
          'association_key_on_join_table' => reflection.association_foreign_key
        }
      when :has_one, :has_many
        {
          'key_position'                  => 'association_table',
          'save_order_constraints'        => ["#{self_class}_#{association_class}"],
          'self_key_on_association_table' => reflection.foreign_key
        }
      when :belongs_to
        {
          'key_position'                  => 'self_table',
          'save_order_constraints'        => ["#{association_class}_#{self_class}"],
          'association_key_on_self_table' => reflection.foreign_key
        }
      else
        raise 'should not have reflection macro other than belongs_to has_and_belongs_to_many has_one has_many'
      end
    end
  end

  def implicit_join_table_association(reflection)
    # belongs_to, has_one(without through), has_many(without through) have no implicit join table
    return nil, nil if (reflection.through_reflection.blank? && reflection.macro != :has_and_belongs_to_many)

    if reflection.macro == :has_and_belongs_to_many
      join_table_class = self.class.brand_new_copy_guess_join_table_class(reflection.options[:join_table])
      self_key_on_join_table = reflection.foreign_key
    else
      join_table_class = reflection.through_reflection.class_name
      self_key_on_join_table = reflection.through_reflection.foreign_key
    end
    join_table_instances = join_table_class.constantize.where("#{self_key_on_join_table} = #{self.id}").to_a

    return join_table_class, join_table_instances.map{ |instance| instance.serialize_hash_for_copy(nil) }
  end

  def brand_new_copy(options={})
    final_options = {:callbacks => [], :associations => nil}.merge(options)

    eager_loaded_self = self.class.includes(final_options[:associations]).find(id)

    hash_origin = eager_loaded_self.serialize_hash_for_copy(final_options[:associations])
    hash_copy   = JSON.parse(hash_origin.to_json) # a way to do deep clone

    builder = BrandNewCopyBuilder.new(hash_origin, hash_copy)
    builder.invoke_callback(final_options[:callbacks])
    builder.save

    return hash_copy['id']
  end
end

ActiveRecord::Base.send(:include, ActsAsBrandNewCopy)
