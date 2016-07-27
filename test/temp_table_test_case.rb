module TemporaryTableTestCase
  def initialize(*)
    super
    @test_tables = Set.new
  end

  def setup(*)
    ActiveRecord::Base.connection.schema_cache.clear!
    ActiveSupport::Dependencies::Reference.clear!
  end

  def teardown(*)
    @test_tables.to_a.each do |tt|
      destroy_test_model(tt)
    end
    super
  end

  protected

  def create_test_model(name, columns, create_table: true, &block)
    model_name = name.to_s.classify

    if create_table
      table_name = name.to_s.pluralize
      ActiveRecord::Base.connection.create_table(table_name, &columns)
      @test_tables << table_name
    end

    Class.new(ActiveRecord::Base) do |c|
      raise "Model already defined: #{model_name}" if Object.const_defined?(model_name, false)
      Object.const_set(model_name, self)
      self.primary_key = :id
      class_eval(&block) if block_given?
      reset_column_information
    end
  end

  def destroy_test_model(name)
    model_name = name.to_s.classify
    clazz = Object.const_get(model_name)

    if clazz.nil?
      raise ArgumentError.new("Can't destroy test model #{name.inspect} - missing!")
    end

    table_name = clazz.table_name
    if clazz.table_exists?
      clazz.connection.drop_table(table_name)
    end
    Object.send(:remove_const, model_name)
    @test_tables.delete(table_name)
  end
end
