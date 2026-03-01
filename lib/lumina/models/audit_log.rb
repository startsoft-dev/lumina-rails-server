# frozen_string_literal: true

module Lumina
  class AuditLog < ActiveRecord::Base
    self.table_name = "audit_logs"

    belongs_to :auditable, polymorphic: true
    belongs_to :user, optional: true

    serialize :old_values, coder: JSON
    serialize :new_values, coder: JSON

    validates :action, presence: true
  end
end
