module Spree
  module Admin
    BaseHelper.class_eval do

      def preference_fields(object, form)
        return unless object.respond_to?(:preferences)
        fields = object.preferences.keys.map do |key|
          next if object.is_a?(Spree::Gateway::IuguGateway) and key == :tax_value_per_months
          if object.has_preference?(key)
            form.label("preferred_#{key}", Spree.t(key) + ": ") +
              preference_field_for(form, "preferred_#{key}", type: object.preference_type(key))
          end
        end
        safe_join(fields, '<br />'.html_safe)
      end

    end
  end
end
