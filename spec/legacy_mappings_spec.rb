require File.dirname(__FILE__) + '/spec_helper'

class MockActiveRecord < ActiveRecord::Base
  set_table_name 'mocks'
  def self.column_names
    %w[id legacy_a legacy_b legacy_c]
  end
  
  def self.columns
    column_names.map do |name|
      ActiveRecord::ConnectionAdapters::Column.new(name.to_s, nil)
    end
  end
end

# test our mock for sanity and requirements for testing

describe MockActiveRecord do
  it "has original column names and can sanitize_sql" do
    MockActiveRecord.column_names.should == %w[id legacy_a legacy_b legacy_c]
    MockActiveRecord.columns.map(&:name).should == %w[id legacy_a legacy_b legacy_c]
    MockActiveRecord.send(:sanitize_sql, :foo => 'bar').should == "`mocks`.`foo` = 'bar'"
  end
end

describe ActiveRecord::Base do
  it "includes ActiveRecord::LegacyMethods::PluginMethods" do
    ActiveRecord::Base.methods.should be_member('uses_legacy_mappings')
  end
end

describe :uses_legacy_mappings do
  it "adds legacy_mappings inheritable hash set to mappings" do
    MockActiveRecord.uses_legacy_mappings mappings = {:legacy_a => :railsy_named_attribute, :legacy_b => :created_on}

    MockActiveRecord.methods.should be_member('legacy_mappings')
    MockActiveRecord.legacy_mappings.should == mappings
  end

  it "extends the class and instance methods" do
    MockActiveRecord.should_receive(:extend).with(ActiveRecord::LegacyMappings::ClassMethods)
    MockActiveRecord.should_receive(:include).with(ActiveRecord::LegacyMappings::InstanceMethods)
    MockActiveRecord.should_receive(:normalize_legacy_field_methods).with(no_args)

    MockActiveRecord.uses_legacy_mappings :legacy_a => :foo
  end
end

describe ActiveRecord::LegacyMappings do
  before do
    @mappings = {:legacy_a => :railsy_named_attribute, :legacy_b => :created_on}
    MockActiveRecord.uses_legacy_mappings @mappings
  end

  describe :column_methods_hash do
    it "adds mappings to column_methods_hash" do
      column_methods_for('railsy_named_attribute').each do |method|
        MockActiveRecord.column_methods_hash[method].should == 'legacy_a'
      end
    
      column_methods_for('created_on').each do |method|
        MockActiveRecord.column_methods_hash[method].should == 'legacy_b'
      end
    end

    it "leaves original mappings alone" do
      column_methods_for('id') do |method|
        MockActiveRecord.column_methods_hash[method].should == 'id'
      end

      column_methods_for('legacy_c') do |method|
        MockActiveRecord.column_methods_hash[method].should == 'legacy_c'
      end
    end

    def column_methods_for(column)
      ["#{column}=", "#{column}?", "#{column}_before_type_cast"].map(&:to_sym)
    end
  end

  describe :column_names_with_legacy_mappings do
    it "should be an array of strings" do
      MockActiveRecord.column_names_with_legacy_mappings.should be_kind_of(Array)
      MockActiveRecord.column_names_with_legacy_mappings.each do |c|
        c.should be_kind_of(String)
      end
    end

    it "should use a merge of legacy columns and mapped columns" do
      MockActiveRecord.column_names_with_legacy_mappings.should ==
        %w[id railsy_named_attribute created_on legacy_c]
    end
  end

  describe :merge_conditions do
    describe :map_legacy_condition do
      it "remains nil when nil" do
        MockActiveRecord.send(:map_legacy_condition, nil).should be_nil
      end

      it "remains the original when not a hash" do
        MockActiveRecord.send(:map_legacy_condition, 'foo').should == 'foo'
      end
    
      it "maps legacy and mappings correctly" do
        MockActiveRecord.send(:map_legacy_condition, :id => 1, :railsy_named_attribute => 'foo').should == {:id => 1, :legacy_a => 'foo'}
      end
    end

    describe :map_legacy_conditions do
      it "removes nils" do
        MockActiveRecord.send(:map_legacy_conditions, ['a',nil,'b']).should == %w[a b]
      end
    
      it "uses map_legacy_condition to create array" do
        MockActiveRecord.should_receive(:map_legacy_condition).and_return('foo', 'bar')
        MockActiveRecord.send(:map_legacy_conditions, %w[a b]).should == %w[foo bar]
      end
    
    end
    
    it "uses map_legacy_conditions to create conditions" do
      MockActiveRecord.should_receive(:map_legacy_conditions).and_return([{:foo => 1}, {:bar => 2}])
      MockActiveRecord.merge_conditions.should == '(`mocks`.`foo` = 1) AND (`mocks`.`bar` = 2)'
    end
  end

  describe :normalize_legacy_field_methods do
    it "doesn't create methods for primary key" do
      field_methods(:id).each do |arg|
        MockActiveRecord.should_not_receive(:define_method).with(arg)
      end
      MockActiveRecord.send(:normalize_legacy_field_methods)
    end

    it "doesn't create methods for original columns" do
      field_methods(:legacy_c).each do |arg|
        MockActiveRecord.should_not_receive(:define_method).with(arg)
      end
      MockActiveRecord.send(:normalize_legacy_field_methods)
    end

    it "creates methods for legacy mapping columns" do
      (field_methods(:railsy_named_attribute) + field_methods(:created_on)).each do |arg|
        MockActiveRecord.should_receive(:define_method).with(arg)
      end
      MockActiveRecord.send(:normalize_legacy_field_methods)
    end
    
    def field_methods(column)
      [column, "#{column}=", "#{column}?"]
    end
  end

  describe :column_for_attribute do
    before do
      @mock = MockActiveRecord.new
    end
    
    it "can get column (name) for original columns" do
      MockActiveRecord.column_names.map(&:to_s).each do |column_name|
        @mock.column_for_attribute(column_name).name.should == column_name
      end
    end

    it "cannot get column (name) for original columns with a symbol, leaves original alone" do
      MockActiveRecord.column_names.map(&:to_s).each do |column_name|
        @mock.column_for_attribute(column_name).name.should == column_name
      end
    end

    it "can get column (name) for legacy mappings" do
      @mappings.each do |column_name, mapping_name|
        @mock.column_for_attribute(mapping_name.to_s).name.should == column_name.to_s
      end
    end

    it "can get column (name) for legacy mappings with a symbol" do
      @mappings.each do |column_name, mapping_name|
        @mock.column_for_attribute(mapping_name).name.should == column_name.to_s
      end
    end
  end
end

