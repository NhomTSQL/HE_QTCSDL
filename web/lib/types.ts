export type Lang = 'en' | 'vi';

export type SessionUser = {
  id: number;
  username: string;
  full_name: string | null;
  role: string;
};

export type NodeRow = {
  id: number;
  name: string;
  hostname?: string | null;
  ip_address?: string | null;
  mac_address?: string | null;
  rack_id?: number | null;
  rack_name: string | null;
  room_id?: number | null;
  room_name: string | null;
  site_id?: number | null;
  site_name: string | null;
  rack_position_u?: number | null;
  power_consumption_watts?: number | null;
  status: string;
  last_ping_at: string | null;
  collected_at: string | null;
  cpu_usage_percent: number | null;
  memory_usage_percent: number | null;
  disk_usage_percent: number | null;
  temperature_celsius?: number | null;
  container_count?: number | null;
  open_alert_count?: number | null;
  primary_marker_code?: string | null;
};

export type RackRow = {
  id: number;
  name: string;
  code: string;
  unit_capacity: number;
  total_power_capacity_watts: number;
  room_id: number;
  room_name: string;
  room_code: string;
  floor: string | null;
  site_id: number;
  site_name: string;
  site_code: string;
  node_count: number;
  used_power_watts: number;
};

export type ContainerRow = {
  id: number;
  node_id: number;
  node_name: string;
  hostname: string;
  container_id: string;
  name: string;
  image: string;
  status: string;
  cpu_usage_percent: number;
  memory_usage_mb: number;
  restarted_count: number;
  created_at: string;
  updated_at: string;
};

export type AlertRow = {
  id: number;
  node_id: number;
  node_name: string;
  alert_type: string;
  severity: string;
  status: string;
  message: string;
  metric_value: number;
  triggered_at: string;
  acknowledged_at?: string | null;
};

export type ThresholdRow = {
  id: number;
  metric_type_id: number;
  metric_code: string;
  unit: string | null;
  description: string | null;
  warning_threshold: number;
  critical_threshold: number;
  duration_seconds: number;
  is_active: boolean;
  updated_at: string;
};

export type TicketRow = {
  id: number;
  alert_id: number | null;
  node_id: number;
  node_name: string;
  title: string;
  description: string;
  priority: string;
  status: string;
  assigned_to_user_id?: number | null;
  assigned_to_username: string | null;
  created_by_username: string | null;
  created_at: string;
  updated_at: string;
  closure_status?: string | null;
  closure_summary?: string | null;
  closure_resolution_details?: string | null;
  closure_requested_by_username?: string | null;
  note_count?: number | null;
};

export type TicketNoteRow = {
  id: number;
  ticket_id: number;
  author_user_id: number;
  author_username: string;
  author_full_name: string;
  note_text: string;
  created_at: string;
};

export type TechnicianOption = {
  id: number;
  username: string;
  full_name: string;
  role_name: string;
};

export type AssetRow = {
  node_id: number;
  node_name: string;
  hostname: string;
  ip_address: string;
  site_name: string;
  room_name: string;
  rack_name: string;
  cpu_model: string | null;
  cpu_cores: number | null;
  total_ram_gb: number | null;
  total_storage_gb: number | null;
  os_name: string | null;
  os_version: string | null;
  nics: string | null;
  vendor: string | null;
  model_number: string | null;
  serial_number: string | null;
  warranty_end: string | null;
  support_contact: string | null;
  days_remaining: number | null;
  warranty_status: string;
};

export type MaintenanceRow = {
  id: number;
  node_id: number;
  node_name: string;
  ticket_id: number | null;
  ticket_title: string | null;
  maintenance_type: string;
  description: string;
  performed_by_user_id: number;
  performed_by_username: string;
  performed_at: string;
  resolution_notes: string | null;
};

export type TelemetryPoint = {
  id: number;
  node_id: number;
  metric_type: string;
  unit: string | null;
  value: number;
  timestamp: string;
};

export type AnalyticsSummary = {
  active_nodes: number;
  total_nodes: number;
  avg_cpu_5min: number | null;
  max_temp_5min: number | null;
  open_alerts: number;
  active_tickets: number;
  avg_mttr_minutes: number;
  current_pue: number;
  it_power_watts: number;
  total_facility_watts: number;
  it_energy_kwh_per_day: number;
  total_energy_kwh_per_day: number;
  active_collectors: number;
  total_containers: number;
  running_containers: number;
  warranty_attention_count: number;
};

export type RackCapacityRow = {
  site_id: number;
  site_name: string;
  room_id: number;
  room_name: string;
  rack_id: number;
  rack_name: string;
  rack_code: string;
  unit_capacity: number;
  node_count: number;
  used_u: number;
  total_power_capacity_watts: number;
  used_power_watts: number;
  avg_cpu_percent: number | null;
  avg_ram_percent: number | null;
  avg_disk_percent: number | null;
  max_temp_celsius: number | null;
};

export type UserRow = {
  id: number;
  username: string;
  email: string;
  full_name: string;
  role_id: number;
  role_name: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type AuditLogRow = {
  id: number;
  user_id: number | null;
  username: string | null;
  action: string;
  target_entity: string;
  target_id: string | null;
  details_json: string | null;
  ip_address: string | null;
  timestamp: string;
};

export type NotificationRow = {
  id: number;
  user_id: number;
  title: string;
  message: string;
  type: string;
  is_read: boolean;
  created_at: string;
};

export type SiteRoomRow = {
  site_id: number;
  site_name: string;
  site_code: string;
  site_location: string | null;
  room_id: number | null;
  room_name: string | null;
  room_code: string | null;
  room_floor: string | null;
};

export type HierarchicalReportRow = {
  group_id: number;
  group_label: string;
  group_by: string;
  node_count: number;
  total_power_watts: number;
  running_containers: number;
  open_alerts: number;
  open_tickets: number;
  sample_count: number;
  avg_cpu_percent: number | null;
  max_cpu_percent: number | null;
  avg_ram_percent: number | null;
  avg_disk_percent: number | null;
  max_temp_celsius: number | null;
};

export type CollectorAgentRow = {
  id: number;
  node_id: number;
  node_name: string;
  hostname: string;
  ip_address: string;
  rack_name: string;
  agent_version: string;
  status: string;
  last_heartbeat_at: string | null;
  seconds_since_heartbeat: number | null;
  created_at: string;
  updated_at: string;
};

export type MarkerLookupResult = {
  node: {
    node_id: number;
    node_name: string;
    hostname: string;
    ip_address: string;
    mac_address: string | null;
    status: string;
    rack_position_u: number;
    power_consumption_watts: number;
    last_ping_at: string | null;
    site_name: string;
    room_name: string;
    rack_name: string;
    marker_code: string;
    marker_type: string;
    coord_x: number | null;
    coord_y: number | null;
    coord_z: number | null;
    cpu_usage_percent: number | null;
    memory_usage_percent: number | null;
    disk_usage_percent: number | null;
    temperature_celsius: number | null;
    collected_at: string | null;
    cpu_model: string | null;
    cpu_cores: number | null;
    total_ram_gb: number | null;
    total_storage_gb: number | null;
    os_name: string | null;
    os_version: string | null;
    vendor: string | null;
    model_number: string | null;
    serial_number: string | null;
    warranty_end: string | null;
    support_contact: string | null;
  };
  containers: ContainerRow[];
  alerts: AlertRow[];
  tickets: TicketRow[];
  maintenance_histories: MaintenanceRow[];
};
