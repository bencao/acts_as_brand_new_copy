module ActsAsBrandNewCopy
  module Merge

    def self.deep_merge(hash, another_hash)
      (hash.keys + another_hash.keys).reduce({}) do |result, key|
        result[key] = (hash[key] || []) + (another_hash[key] || [])
        result
      end
    end

  end
end
