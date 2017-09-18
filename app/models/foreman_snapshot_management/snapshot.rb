require 'date'

module ForemanSnapshotManagement
  class Snapshot
    extend ActiveModel::Callbacks
    include ActiveModel::Conversion
    include ActiveModel::Model
    include ActiveModel::Dirty
    include ActiveModel::ForbiddenAttributesProtection

    define_model_callbacks :create, :save, :destroy, :revert
    attr_accessor :id, :raw_snapshot, :name, :description, :host_id, :parent, :create_time

    def self.all_for_host(host)
      snapshots = host.compute_resource.get_snapshots(host.uuid).map do |raw_snapshot|
        new_from_vmware(host, raw_snapshot)
      end
    end

    def self.find_for_host(host, id)
      raw_snapshot = host.compute_resource.get_snapshot(host.uuid, id)
      new_from_vmware(host, raw_snapshot)
    end

    def self.new_from_vmware(host, raw_snapshot, opts = {})
      new(
        host: host,
        id: raw_snapshot.ref,
        raw_snapshot: raw_snapshot,
        name: raw_snapshot.name,
        description: raw_snapshot.description,
        parent: opts[:parent],
        create_time: raw_snapshot.create_time
      )
    end

    def children
      return [] unless raw_snapshot
      child_snapshots = raw_snapshot.child_snapshots.flat_map do |child_snapshot|
        self.class.new_from_vmware(host, child_snapshot, parent: self)
      end
      child_snapshots + child_snapshots.flat_map(&:children)
    end

    def inspect
      "#<#{self.class}:0x#{self.__id__.to_s(16)} name=#{name} id=#{id} description=#{description} host_id=#{host_id} parent=#{parent.try(:id)} children=#{children.map(&:id).inspect}>"
    end

    def to_s
      _('Snapshot')
    end

    def formatted_create_time()
      create_time.strftime("%F %H:%M")
    end

    def persisted?
      self.id.present?
    end

    # host accessors
    def host
      Host.find(self.host_id)
    end

    def host=(host)
      self.host_id = host.id
    end

    def create_time
      raw_snapshot.try(:create_time)
    end

    def assign_attributes(new_attributes)
      attributes = new_attributes.stringify_keys
      attributes = sanitize_for_mass_assignment(attributes)
      attributes.each do |k, v|
        public_send("#{k}=", v)
      end
    end

    def update_attributes(new_attributes)
      assign_attributes(new_attributes)
      save
    end

    # crud
    def create
      run_callbacks(:create) do
        handle_snapshot_errors do
          host.compute_resource.create_snapshot(host.uuid, name, description)
        end
      end
    end

    def save
      run_callbacks(:save) do
        handle_snapshot_errors do
          host.compute_resource.update_snapshot(raw_snapshot, name, description)
        end
      end
    end

    def destroy
      run_callbacks(:destroy) do
        result = handle_snapshot_errors do
          result = host.compute_resource.remove_snapshot(raw_snapshot, false)
        end
        self.id = nil
        result
      end
    end

    def revert
      run_callbacks(:revert) do
        handle_snapshot_errors do
          host.compute_resource.revert_snapshot(raw_snapshot)
        end
      end
    end

    private

    def handle_snapshot_errors
      yield
    rescue Foreman::WrappedException => e
      errors.add(:base, e.wrapped_exception.message)
      false
    end
  end
end
