require 'acts_as_brand_new_copy/merge'
require 'acts_as_brand_new_copy/standard'

module ActsAsBrandNewCopy
  class Serializer

    def initialize(record, associations = [])
      @record       = record
      @associations = associations || []
    end

    # sample associations = [
    #   :billing_term_condition,
    #   {:line_items => [:targeting_criteria]},
    #   :resource_user_assignments
    # ]
    def serialize
      hash = quoted_attributes_for_copy

      @associations.each do |association|
        if association.is_a?(Symbol)
          hash['dependencies'] = Merge.deep_merge(hash['dependencies'], serialize_dependencies(association))
          hash['associations'] = Merge.deep_merge(hash['associations'], serialize_associations(association, []))
        else
          child_association        = association.keys.first
          child_association_option = association.values.first
          hash['dependencies'] = Merge.deep_merge(hash['dependencies'], serialize_dependencies(child_association))
          hash['associations'] = Merge.deep_merge(hash['associations'], serialize_associations(child_association, child_association_option))
        end
      end

      hash
    end

    private

    def quoted_attributes_for_copy
      quoted_attributes = quoted_attributes_from_ar_attributes
      # in case the table has no id
      unless quoted_attributes.key?('id')
        quoted_attributes['id'] = quoted_attributes.values.join('_')
      end
      quoted_attributes['klass']          = Standard.absolute_klass_name(@record.class.to_s)
      quoted_attributes['associations']   = {}
      quoted_attributes['dependencies']   = {}
      quoted_attributes['id_before_copy'] = quoted_attributes['id']
      quoted_attributes
    end

    def quoted_attributes_from_ar_attributes
      quoted_attributes = {}
      @record.attributes.each_pair do |key, value|
        case value.class.to_s
        when 'Date', 'Time', 'ActiveSupport::TimeWithZone'
          quoted_attributes[key] = connection.quoted_date(value)
        when 'BigDecimal'
          quoted_attributes[key] = value.to_s('F')
        else
          quoted_attributes[key] = value
        end
      end
      quoted_attributes
    end

    def serialize_dependencies(association)
      reflection = @record.class.reflect_on_association(association)
      class_name = Standard.reflection_association_name(reflection)

      # has_one through OR has_many through
      if reflection.through_reflection.present?
        { class_name => [copy_dependencies_for_through(reflection)] }
      else
        { class_name => [copy_dependencies_for_macros(reflection)] }
      end
    end

    def serialize_associations(association, option)
      reflection = @record.class.reflect_on_association(association)
      class_name = Standard.reflection_association_name(reflection)

      implicit_associations(reflection).merge(class_name => explicit_association(association, option))
    end

    def explicit_association(association, option)
      records = @record.send(association)

      return [] if records.blank?

      records = [records] unless records.is_a?(Array)

      records.map do |record|
        self.class.new(record, option).serialize
      end
    end

    def implicit_associations(reflection)
      if reflection.macro == :has_and_belongs_to_many
        serialize_has_and_belongs_to_many_association(reflection)
      elsif reflection.through_reflection.present?
        serialize_through_association(reflection)
      else
        {}
      end
    end

    def serialize_has_and_belongs_to_many_association(reflection)
      name      = guess_join_table_class(reflection)
      key       = reflection.foreign_key
      records   = name.constantize.where("#{key} = #{@record.id}").to_a

      { name => records.map { |record| self.class.new(record).serialize } }
    end

    def serialize_through_association(reflection)
      name      = Standard.reflection_association_name(reflection.through_reflection)
      key       = reflection.through_reflection.foreign_key
      records   = name.constantize.where("#{key} = #{@record.id}").to_a

      { name => records.map { |record| self.class.new(record).serialize } }
    end

    def copy_dependencies_for_through(reflection)
      copy_dependencies_for_join_type(
        Standard.reflection_self_name(reflection),
        Standard.reflection_association_name(reflection),
        Standard.reflection_association_name(reflection.through_reflection),
        reflection.through_reflection.foreign_key,
        reflection.source_reflection.foreign_key
      )
    end

    def copy_dependencies_for_macros(reflection)
      case (reflection.macro)
      when :has_and_belongs_to_many
        copy_dependencies_for_has_and_belongs_to_many(reflection)
      when :has_one, :has_many
        copy_dependencies_for_has_one_or_has_many(reflection)
      when :belongs_to
        copy_dependencies_for_belongs_to(reflection)
      else
        {}
      end
    end

    def copy_dependencies_for_has_and_belongs_to_many(reflection)
      copy_dependencies_for_join_type(
        Standard.reflection_self_name(reflection),
        Standard.reflection_association_name(reflection),
        guess_join_table_class(reflection),
        reflection.foreign_key,
        reflection.association_foreign_key
      )
    end

    def copy_dependencies_for_has_one_or_has_many(reflection)
      self_class                    = Standard.reflection_self_name(reflection)
      association_class             = Standard.reflection_association_name(reflection)
      self_key_on_association_table = reflection.foreign_key
      {
        'key_position'                  => 'association_table',
        'save_order_constraints'        => ["#{self_class}_#{association_class}"],
        'self_key_on_association_table' => self_key_on_association_table
      }
    end

    def copy_dependencies_for_belongs_to(reflection)
      self_class                    = Standard.reflection_self_name(reflection)
      association_class             = Standard.reflection_association_name(reflection)
      association_key_on_self_table = reflection.foreign_key
      {
        'key_position'                  => 'self_table',
        'save_order_constraints'        => ["#{association_class}_#{self_class}"],
        'association_key_on_self_table' => association_key_on_self_table
      }
    end

    def copy_dependencies_for_join_type(
          self_class,
          association_class,
          join_table_class,
          self_key_on_join_table,
          association_key_on_join_table
        )
      {
        'key_position'                  => 'join_table',
        'save_order_constraints'        => [
          "#{self_class}_#{join_table_class}",
          "#{association_class}_#{join_table_class}",
          "#{association_class}_#{self_class}"
        ],
        'join_table_class'              => join_table_class,
        'self_key_on_join_table'        => self_key_on_join_table,
        'association_key_on_join_table' => association_key_on_join_table
      }
    end

    def guess_join_table_class(reflection)
      name = reflection.options[:join_table]
      [name.singularize, name.pluralize].each do |candidate|
        camelized_name = candidate.camelize
        if Object.const_defined?(camelized_name)
          return Standard.absolute_klass_name(camelized_name)
        end
      end
      raise "do not know how to map join table '#{name}' to ActiveRecord class"
    end
  end
end
