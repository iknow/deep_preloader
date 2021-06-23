class DeepPreloader::AbstractSpec
  def for_type(clazz)
    raise ArgumentError.new("Cannot type dispatch on non-polymorphic preload spec #{self.inspect}")
  end

  def polymorphic?
    false
  end
end
