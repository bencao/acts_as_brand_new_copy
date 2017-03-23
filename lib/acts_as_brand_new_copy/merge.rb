module ActsAsBrandNewCopy
  module Merge
    def self.deep_merge(hash, another_hash)
      (hash.keys + another_hash.keys).each_with_object({}) do |key, merged|
        merged[key] = (hash[key] || []) + (another_hash[key] || [])
      end
    end
  end
end
