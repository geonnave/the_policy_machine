policy_machine
==============

A ruby implementation of the Policy Machine authorization formalism.  You can find the NIST specification for Policy
Machines [here](http://csrc.nist.gov/pm/documents/pm_report-rev-x_final.pdf).

Note that obligations have not yet been implemented, nor have all aspects of prohibitions and policy classes.  These aspects of the Policy Machine
will be included in future versions of this gem.

# Installation

Add the following to your Gemfile:
```
gem 'policy_machine'
```

# Usage
```
require 'policy_machine'
require 'policy_machine_storage_adapters/in_memory'

policy_machine = PolicyMachine.new('my_policy_machine', ::PolicyMachineStorageAdapter::InMemory)

# This PM is taken from the policy machine spec at http://csrc.nist.gov/pm/documents/pm_report-rev-x_final.pdf,
# Figure 4. (pg. 19)

# Users
u1 = policy_machine.create_user('u1')
u2 = policy_machine.create_user('u2')
u3 = policy_machine.create_user('u3')

# Objects
o1 = policy_machine.create_object('o1')
o2 = policy_machine.create_object('o2')
o3 = policy_machine.create_object('o3')

# User Attributes
group1 = policy_machine.create_user_attribute('Group1')
group2 = policy_machine.create_user_attribute('Group2')
division = policy_machine.create_user_attribute('Division')

# Object Attributes
project1 = policy_machine.create_object_attribute('Project1')
project2 = policy_machine.create_object_attribute('Project2')
projects = policy_machine.create_object_attribute('Projects')

# Operations
r = policy_machine.create_operation('read')
w = policy_machine.create_operation('write')

# Assignments
policy_machine.add_assignment(u1, group1)
policy_machine.add_assignment(u2, group2)
policy_machine.add_assignment(u3, division)
policy_machine.add_assignment(group1, division)
policy_machine.add_assignment(group2, division)
policy_machine.add_assignment(o1, project1)
policy_machine.add_assignment(o2, project1)
policy_machine.add_assignment(o3, project2)
policy_machine.add_assignment(project1, projects)
policy_machine.add_assignment(project2, projects)

# Associations
policy_machine.add_association(group1, Set.new([w]), project1)
policy_machine.add_association(group2, Set.new([w]), project2)
policy_machine.add_association(division, Set.new([r]), projects)

# List all privileges encoded in the policy machine
policy_machine.privileges

# Returns true
policy_machine.is_privilege?(u1, w, o1)

# Returns false
policy_machine.is_privilege?(u3, w, o3)
```

# Prohibitions
prohibit_w = w.prohibition
policy_machine.add_association(division, Set.new([r,prohibit_w]),project1)
# division cannot gain w on project1, no matter what other associations are added.

# Storage Adapters

Note that the Policy Machine in the above example stores policy elements in memory.  Other persistent
storage options are available in `lib/policy_machine_storage_adapters`.

*Neography*

The Neography storage adapter uses the neo4j graph database, which must be installed separately,
and `gem 'neography'`. This should not be used in production since the interface is slow.

*ActiveRecord*

The ActiveRecord storage adapter talks to your existing MySQL database via your preconfigured
ActiveRecord. You'll need to run `rails generate policy_machine migration` to add the necessary
tables to your database.

If you'd like to make your own storage adapter, see See [CONTRIBUTING.md](CONTRIBUTING.md).

# Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
