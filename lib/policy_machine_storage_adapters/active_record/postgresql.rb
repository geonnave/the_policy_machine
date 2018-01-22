require 'active_record/hierarchical_query' # via gem activerecord-hierarchical_query

module PolicyMachineStorageAdapter
  class ActiveRecord
    class Assignment < ::ActiveRecord::Base
      # needs parent_id, child_id columns
      belongs_to :parent, class_name: 'PolicyElement', foreign_key: :parent_id
      belongs_to :child, class_name: 'PolicyElement', foreign_key: :child_id

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor).include?(descendant)
      end

      def self.descendants_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive AS (
              (
                SELECT child_id, parent_id
                FROM assignments
                WHERE parent_id in (?)
              )
              UNION ALL
              (
                SELECT assignments.child_id, assignments.parent_id
                FROM assignments
                INNER JOIN assignments_recursive
                ON assignments_recursive.child_id = assignments.parent_id
              )
            )

            SELECT assignments_recursive.child_id
            FROM assignments_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      def self.ancestors_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive AS (
              (
                SELECT parent_id, child_id
                FROM assignments
                WHERE child_id IN (?)
              )
              UNION ALL
              (
                SELECT assignments.parent_id, assignments.child_id
                FROM assignments
                INNER JOIN assignments_recursive
                ON assignments_recursive.parent_id = assignments.child_id
              )
            )

            SELECT assignments_recursive.parent_id
            FROM assignments_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      # Return an ActiveRecord::Relation containing the ids of all ancestors and the
      # interstitial relationships, as a string of ancestor_ids
      def self.find_ancestor_ids(root_element_ids)
        query = <<-SQL
          WITH RECURSIVE assignments_recursive AS (
            (
              SELECT parent_id, child_id
              FROM assignments
              WHERE #{sanitize_sql_for_conditions(["child_id IN (:root_ids)", root_ids: root_element_ids])}
            )
            UNION ALL
            (
              SELECT assignments.parent_id, assignments.child_id
              FROM assignments
              INNER JOIN assignments_recursive
              ON assignments_recursive.parent_id = assignments.child_id
            )
          )

          SELECT child_id as id, array_agg(parent_id) as ancestor_ids
          FROM assignments_recursive
          GROUP BY child_id
        SQL

        PolicyElement.connection.exec_query(query)
      end

      def self.ancestors_filtered_by_policy_element_associations(element, policy_element_association_ids)
        query = <<-SQL
          id IN (
            WITH RECURSIVE assignments_recursive(parent_id, child_id, matching_policy_element_association_id) AS (
              (
                SELECT parent_id, child_id, policy_element_associations.id
                FROM assignments
                LEFT OUTER JOIN policy_element_associations 
                  ON assignments.parent_id = policy_element_associations.object_attribute_id AND
                    policy_element_associations.id IN (:policy_element_association_ids)
                WHERE child_id = :accessible_scope_id
              )
              UNION
              (
                SELECT assignments.parent_id, assignments.child_id, policy_element_associations.id 
                FROM assignments
                INNER JOIN assignments_recursive ON assignments_recursive.parent_id = assignments.child_id
                LEFT OUTER JOIN policy_element_associations
                  ON assignments_recursive.parent_id = policy_element_associations.object_attribute_id AND 
                    policy_element_associations.id IN (:policy_element_association_ids)
                WHERE assignments_recursive.matching_policy_element_association_id IS NULL 
              )
            )
          
            SELECT assignments_recursive.child_id
            FROM assignments_recursive
            WHERE matching_policy_element_association_id IS NOT NULL
          )
        SQL

        PolicyElement.where(query,
          accessible_scope_id: element.id,
          policy_element_association_ids: policy_element_association_ids)
      end

      def self.accessible_ancestors_filtered_by_policy_element_associations_and_object_descendants_or_something(element, policy_element_association_ids)
        query = <<-SQL
          id IN (
            WITH candidate_policy_elements(policy_element_association_id, policy_element_id) AS (
              SELECT id, object_attribute_id
              FROM policy_element_associations
              WHERE policy_element_association_id IN (:policy_element_association_ids)
            )
          
            SELECT id
            FROM policy_elements
            WHERE id IN (
              WITH RECURSIVE assignments_recursive(parent_id, child_id, matching_policy_element_association_id AS (
                (
                  SELECT asg1.parent_id, asg1.child_id, cpe1.policy_element_association_id
                  FROM assignments AS asg1
                  LEFT OUTER JOIN candidate_policy_elements AS cpe1 ON asg1.parent_id = cpe1.policy_element_id OR cpe1.policy_element_association_id IN (
                    #{complicated_candidate_policy_elements_join_conditions}
                  )
                  WHERE child_id = :accessible_scope_id
                )
                UNION
                (
                  SELECT asg1.parent_id, asg1.child_id, cp1.policy_element_association_id
                  FROM assignments AS asg1
                  INNER JOIN assignments_recursive
                  LEFT OUTER JOIN candidate_policy_elements AS cpe1 ON assignments_recursive.parent_id = cpe1.policy_element_id OR cpe1.policy_element_association_id IN (
                    #{complicated_candidate_policy_elements_join_conditions}
                  )
                  WHERE assignments_recursive.matching_policy_element_association_id IS NULL
                )
              )
          
              SELECT assignments_recursive.child_id
              FROM assignments_recursive
              WHERE matching_policy_element_association_id IS NOT NULL
            )
          )
        SQL

        PolicyElement.where(query,
          accessible_scope_id: element.id,
          policy_element_association_ids: policy_element_association_ids)
      end

      def complicated_candidate_policy_elements_join_conditions
        <<-SQL
          WITH RECURSIVE child_assignments_recursive(parent_id, child_id, matching_policy_element_association_id) AS (
            (
              SELECT asg2.parent_id, asg2.child_id, cpe2.policy_element_association_id
              FROM assignments AS asg2
              LEFT OUTER JOIN candidate_policy_elements AS cpe2 ON asg2.child_id = cpe2.policy_element_id
              WHERE asg2.parent_id = asg1.parent_id AND asg2.child_id != asg2.child_id
            )
            UNION
            (
              SELECT asg3.parent_id, asg3.child_id, cpe3.policy_element_association_id
              FROM assignments AS asg3
              INNER JOIN child_assignments_recursive ON child_assignments_recursive.child_id = assignments.parent_id
              LEFT OUTER JOIN candidate_policy_elements AS cpe3 ON cpe3.policy_element_id = child_assignments_recursive.child_id
              WHERE assignments_recursive.matching_policy_element_association_id IS NULL AND NOT EXISTS (
                SELECT 1 FROM assignments_recursive WHERE matching_policy_element_association_id IS NOT NULL
              )
            )
          )

          SELECT child_assignments_recursive.matching_policy_element_association_id
          FROM child_assignments_recursive
          WHERE child_assignments_recursive.matching_policy_element_association_id IS NOT NULL
          LIMIT 1
        SQL
      end

      # Returns the operation set IDs from the given list where the operation is
      # a descendant of the operation set.
      # TODO: Generalize this so that we can arbitrarily filter recursive assignments calls.
      def self.filter_operation_set_list_by_assigned_operation(operation_set_ids, operation_id)
        query = <<-SQL
          WITH RECURSIVE assignments_recursive AS (
            (
              SELECT parent_id, child_id, ARRAY[parent_id] AS parents
              FROM assignments
              WHERE #{sanitize_sql_for_conditions(["parent_id IN (:opset_ids)", opset_ids: operation_set_ids])}
            )
            UNION ALL
            (
              SELECT assignments.parent_id, assignments.child_id, (parents || assignments.parent_id)
              FROM assignments
              INNER JOIN assignments_recursive
              ON assignments_recursive.child_id = assignments.parent_id
            )
          )

          SELECT parents[1]
          FROM assignments_recursive
          JOIN policy_elements 
          ON policy_elements.id = assignments_recursive.child_id
          WHERE #{sanitize_sql_for_conditions(["policy_elements.unique_identifier=:op_id", op_id: operation_id])}
          AND type = 'PolicyMachineStorageAdapter::ActiveRecord::Operation'
        SQL

        PolicyElement.connection.exec_query(query).rows.flatten.map(&:to_i)
      end
    end

    class LogicalLink < ::ActiveRecord::Base

      belongs_to :link_parent, class_name: 'PolicyElement', foreign_key: :link_parent_id
      belongs_to :link_child, class_name: 'PolicyElement', foreign_key: :link_child_id

      def self.transitive_closure?(ancestor, descendant)
        descendants_of(ancestor).include?(descendant)
      end

      def self.descendants_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE logical_links_recursive AS (
              (
                SELECT link_child_id, link_parent_id
                FROM logical_links
                WHERE link_parent_id in (?)
              )
              UNION ALL
              (
                SELECT logical_links.link_child_id, logical_links.link_parent_id
                FROM logical_links
                INNER JOIN logical_links_recursive
                ON logical_links_recursive.link_child_id = logical_links.link_parent_id
              )
            )

            SELECT logical_links_recursive.link_child_id
            FROM logical_links_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end

      def self.ancestors_of(element_or_scope)
        query = <<-SQL
          id IN (
            WITH RECURSIVE logical_links_recursive AS (
              (
                SELECT link_parent_id, link_child_id
                FROM logical_links
                WHERE link_child_id IN (?)
              )
              UNION ALL
              (
                SELECT logical_links.link_parent_id, logical_links.link_child_id
                FROM logical_links
                INNER JOIN logical_links_recursive
                ON logical_links_recursive.link_parent_id = logical_links.link_child_id
              )
            )

            SELECT logical_links_recursive.link_parent_id
            FROM logical_links_recursive
          )
        SQL

        PolicyElement.where(query, [*element_or_scope].map(&:id))
      end
    end

    class Adapter
      # Support substring searching and Postgres Array membership
      def self.apply_include_condition(scope: , key: , value: , klass: )
        if klass.columns_hash[key.to_s].array
          [*value].reduce(scope) { |rel, val| rel.where("? = ANY(#{key})", val) }
        else
          scope.where("#{key} LIKE '%#{value.to_s.gsub(/([%_])/, '\\\\\0')}%'", )
        end
      end
    end
  end
end
