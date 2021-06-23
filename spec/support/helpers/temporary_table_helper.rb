module TemporaryTableHelper
  extend ActiveSupport::Concern

  class_methods do
    def with_temporary_table(name, columns = ->(t){}, superclass: -> { ActiveRecord::Base }, create_table: true, &block)
      table_builder = nil

      before(:context) do
        ActiveRecord::Base.connection.schema_cache.clear!
        ActiveSupport::Dependencies::Reference.clear!
        table_builder = TableBuilder.new(name, columns, superclass: superclass.(), create_table: create_table, &block)
      end

      after(:context) do
        table_builder.teardown
      end
    end
  end

  class TableBuilder
    def initialize(name, columns, superclass:, create_table:, &block)
      @create_table = create_table
      @superclass = superclass

      model_name = name.to_s.classify

      if create_table
        table_name = name.to_s.pluralize
        ActiveRecord::Base.connection.create_table(table_name, &columns)
      end

      @model_class =
        Class.new(@superclass) do |_c|
          raise "Model already defined: #{model_name}" if Object.const_defined?(model_name, false)

          Object.const_set(model_name, self)
          self.primary_key = :id
          class_eval(&block) if block_given?
          reset_column_information
        end
    end

    def teardown
      if @model_class.nil?
        raise ArgumentError.new("Can't destroy test model #{name.inspect} - missing!")
      end

      if @create_table
        @model_class.connection.drop_table(@model_class.table_name)
      end

      model_name = @model_class.name
      Object.send(:remove_const, model_name)
    end
  end
end
