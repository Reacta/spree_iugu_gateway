require 'spree_core'
require 'spree_iugu_gateway/engine'
require 'spree_iugu_gateway/exceptions'

Spree::PermittedAttributes.source_attributes.push [:installments]
