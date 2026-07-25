# frozen_string_literal: true

module Custom::Account
  extend ActiveSupport::Concern

  included do
    # Ejemplo: agregar un scope nuevo
    scope :vendeenone_active, -> { where(is_active: true) }
  end

  # Ejemplo: override de un método existente
  def name
    # Llamar al método original y agregar lógica custom
    formatted_name = super
    "[VendeEnOne] #{formatted_name}"
  end

  # Método totalmente nuevo
  def vendeenone_config
    {
      custom_branding: custom_attributes['branding'] || 'default',
      client_since: created_at
    }
  end
end
