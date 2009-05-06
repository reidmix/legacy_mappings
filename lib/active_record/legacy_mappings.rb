module ActiveRecord
  module LegacyMappings
    def self.included(base)
      base.extend(PluginMethods)
    end

    module PluginMethods
      def uses_legacy_mappings mappings = {}
        self.class_inheritable_hash :legacy_mappings
        self.legacy_mappings = mappings

        self.extend(ClassMethods)
        self.send(:include, InstanceMethods)
        normalize_legacy_field_methods
      end
    end

    module ClassMethods
      def column_methods_hash
        @dynamic_methods_hash ||= column_names.inject(Hash.new(false)) do |methods, attr|
          attr_name = attr.to_s
          updated_attr = self.legacy_mappings[attr.to_sym] || attr_name
          returning(methods) do |m|
            m[updated_attr] = attr_name
            m["#{updated_attr}=".to_sym] = attr_name
            m["#{updated_attr}?".to_sym] = attr_name
            m["#{updated_attr}_before_type_cast".to_sym] = attr_name
          end
        end
      end

      def merge_conditions(*conditions)
        segments = []

        map_legacy_conditions(conditions).each do |condition|
          unless condition.blank?
            sql = sanitize_sql(condition)
            segments << sql unless sql.blank?
          end
        end

        "(#{segments.join(') AND (')})" unless segments.empty?
      end

      protected
        def normalize_legacy_field_methods
          column_names.each do |original_attr|
            next if original_attr == primary_key
            next unless updated_attr = self.legacy_mappings[original_attr.to_sym]

            define_method(updated_attr) do
              read_attribute(original_attr)
            end

            define_method("#{updated_attr}=") do |value|
              write_attribute(original_attr, value)
            end

            define_method("#{updated_attr}?") do
              send("#{original_attr}?")
            end
          end
        end

      private
        def map_legacy_conditions(conditions)
          conditions.inject([]) do |mapped_conditions,condition|
            mapped_conditions << map_legacy_condition(condition) unless condition.blank?
            mapped_conditions
          end
        end

        def map_legacy_condition(condition)
          return nil if condition.blank?
          if Hash === condition
            condition.inject({}) do |h,p|
              k,v = *p
              h[self.legacy_mappings.index(k.to_sym) || k] = v
              h
            end
          else 
            condition
          end
        end
    end

    module InstanceMethods
      def column_for_attribute(name)
        self.class.columns_hash[(mapping = self.legacy_mappings.index(name.to_sym)) && mapping.to_s || name]
      end
    end
  end
end