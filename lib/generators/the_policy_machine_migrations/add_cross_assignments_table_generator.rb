#require 'rails/generators/active_record/migration/migration_generator'
module ThePolicyMachineMigrations
  module Generators
    class AddCrossAssignmentsTableGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../migrations', __FILE__)

      def generate_add_cross_assignments_table_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        copy_file('add_cross_assignments_table.rb', "db/migrate/#{timestamp}_add_cross_assignments_table.rb")
      end
    end
  end
end
