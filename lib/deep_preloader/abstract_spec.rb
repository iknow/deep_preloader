class DeepPreloader::AbstractSpec
  def for_type(clazz)
    raise ArgumentError.new("Cannot type dispatch on non-polymorphic preload spec #{self.inspect}")
  end

  def self.parse_hash_spec(hash_spec)
    normalize = ->(s) do
      case s
      when Array
        s.each_with_object({}) do |v, h|
          h.merge!(normalize.(v))
        end
      when Hash
        s.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = normalize.(v)
        end
      when String, Symbol
        { s.to_sym => nil }
      when nil
        nil
      else
        raise ArgumentError.new("Cannot parse invalid hash preload spec: #{hash_spec.inspect}")
      end
    end

    wrap = ->(h) do
      if h.present?
        h = h.each_with_object({}){ |(k,v), a| a[k] = wrap.(v) }
        DeepPreloader::Spec.new(h)
      end
    end

    wrap.(normalize.(hash_spec))
  end
end
