module ActsAsBrandNewCopy
  module Standard
    def self.absolute_klass_name(name)
      name.start_with?("::") ? "#{name}" : "::#{name}"
    end

    def self.object_key(klass, id)
      absolute_klass_name(klass).constantize.table_name + "_#{id}"
    end
  end
end
