require 'acts_as_brand_new_copy/builder'
require 'acts_as_brand_new_copy/serializer'

module ActsAsBrandNewCopy
  extend ActiveSupport::Concern

  module ClassMethods
    def brand_new_copy_object_key(klass, id)
      Builder.object_key(klass, id)
    end
  end

  def brand_new_copy(options = {})
    callbacks    = sanitize_copy_param('callbacks', options[:callbacks])
    associations = sanitize_copy_param('associations', options[:associations])

    eager_loaded_self = self.class.includes(associations).find(id)
    serializer        = Serializer.new(eager_loaded_self, associations)
    builder           = Builder.new(serializer.serialize)

    builder.invoke_callback(callbacks)
    builder.save

    builder.new_id(self.class.name, id)
  end

  def sanitize_copy_param(name, param)
    return [] if param.nil?

    unless param.is_a?(Array)
      raise "#{name} param must be an array"
    end

    param.uniq!
    param.each do |item|
      unless item.is_a?(Symbol) || item.is_a?(Hash)
        raise "#{name} param must be consist of Symbol and Hash"
      end

      if item.is_a?(Hash)
        sanitize_copy_param(name, item.values.first)
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActsAsBrandNewCopy)
