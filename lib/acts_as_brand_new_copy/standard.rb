module ActsAsBrandNewCopy
  module Standard
    def self.absolute_klass_name(name)
      name.start_with?("::") ? "#{name}" : "::#{name}"
    end

    def self.object_key(klass, id)
      absolute_klass_name(klass).constantize.table_name + "_#{id}"
    end

    def self.object_hash_to_s(hash)
      "class=#{hash['klass']}, id=#{hash['id']}"
    end

    def self.association_klass_name(klass, association)
      absolute_klass_name(klass.reflect_on_association(association).class_name)
    end

    def self.reflection_association_name(reflection)
      absolute_klass_name(reflection.class_name)
    end

    def self.reflection_self_name(reflection)
      absolute_klass_name(reflection.active_record.to_s)
    end
  end
end
