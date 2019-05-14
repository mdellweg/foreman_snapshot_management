module ForemanSnapshotManagement
  module ProxmoxExtensions
    # Extend Proxmox's capabilities with snapshots.
    def capabilities
      super + [:snapshots]
    end

    # Create a Snapshot.
    #
    # This method creates a Snapshot with a given name and optional description.
    def create_snapshot(host, name, description, _include_ram = false)
      server = find_vm_by_uuid host.uuid
      snapshot = server.snapshots.create name
      snapshot.description = description
      snapshot.update
    end

    # Remove Snapshot
    #
    # This method removes a Snapshot from a given host.
    def remove_snapshot(snapshot)
      snapshot.destroy
    end

    # Revert Snapshot
    #
    # This method revert a host to a given Snapshot.
    def revert_snapshot(snapshot)
      snapshot.rollback
    end

    # Update Snapshot
    #
    # This method renames a Snapshot from a given host.
    def update_snapshot(snapshot, name, description)
      client.rename_snapshot('snapshot' => snapshot, 'name' => name, 'description' => description)
      true
    rescue RbVmomi::Fault => e
      Foreman::Logging.exception('Error updating VMWare Snapshot', e)
      raise ::Foreman::WrappedException.new(e, N_('Unable to update VMWare Snapshot'))
    end

    # Get Snapshot
    #
    # This methods returns a specific Snapshot for a given host.
    def get_snapshot(host, snapshot_id)
      server = find_vm_by_uuid host.uuid
      snapshot = server.snapshots.get(snapshot_id)
      raw_to_snapshot(host, snapshot)
    end

    # Get Snapshots
    #
    # This methods returns Snapshots for a given host.
    def get_snapshots(host)
      server = find_vm_by_uuid host.uuid
      snapshot = server.snapshots.map do |snapshot|
        raw_to_snapshot(host, snapshot)
      end
    end

    private

    def raw_to_snapshot(host, raw_snapshot)
      Snapshot.new(
        host: host,
        id: raw_snapshot.name,
        raw_snapshot: raw_snapshot,
        name: raw_snapshot.name,
        description: raw_snapshot.description,
        # create_time: raw_snapshot.create_time
      ) if raw_snapshot
    end

    def task_successful?(task)
      task['task_state'] == 'success' || task['state'] == 'success'
    end
  end
end
