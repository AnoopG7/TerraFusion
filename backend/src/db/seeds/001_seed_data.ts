import type { Knex } from 'knex'
import bcrypt from 'bcryptjs'

export async function seed(knex: Knex) {
  const existing = await knex('users').first()
  if (existing) {
    console.log('Database already seeded, skipping')
    return
  }

  console.log('Seeding database...')

  const hash = await bcrypt.hash('admin123', 10)
  const mHash = await bcrypt.hash('manager123', 10)
  const sHash = await bcrypt.hash('staff123', 10)

  await knex('users').insert([
    { first_name: 'Admin', last_name: 'User', email: 'admin@terrafusion.io', password_hash: hash, role: 'admin', region: 'us-east-1' },
    { first_name: 'Jane', last_name: 'Manager', email: 'manager@terrafusion.io', password_hash: mHash, role: 'manager', region: 'us-east-1' },
    { first_name: 'John', last_name: 'Staff', email: 'staff@terrafusion.io', password_hash: sHash, role: 'staff', region: 'us-west-1' },
    { first_name: 'Sarah', last_name: 'Chen', email: 'sarah@terrafusion.io', password_hash: mHash, role: 'manager', region: 'eu-west-1' },
    { first_name: 'Mike', last_name: 'Johnson', email: 'mike@terrafusion.io', password_hash: sHash, role: 'staff', region: 'us-east-1' },
    { first_name: 'Priya', last_name: 'Patel', email: 'priya@terrafusion.io', password_hash: sHash, role: 'staff', region: 'ap-southeast-1' },
  ])

  await knex('sensor_readings').insert([
    { reading_id: 'SR-1001', sensor_id: 'sat-01', sensor_type: 'satellite', co2_ppm: 415.2, temperature_c: 22.5, humidity: 62, region: 'us-east-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1002', sensor_id: 'sat-02', sensor_type: 'satellite', co2_ppm: 421.8, temperature_c: 28.3, humidity: 55, region: 'us-west-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1003', sensor_id: 'ocean-01', sensor_type: 'oceanographic', co2_ppm: 408.5, temperature_c: 18.1, humidity: 85, region: 'eu-west-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1004', sensor_id: 'weather-01', sensor_type: 'weather', co2_ppm: 432.1, temperature_c: 35.6, humidity: 72, region: 'ap-southeast-1', status: 'anomaly', timestamp: knex.fn.now() },
    { reading_id: 'SR-1005', sensor_id: 'sat-03', sensor_type: 'satellite', co2_ppm: 418.3, temperature_c: 24.0, humidity: 58, region: 'us-east-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1006', sensor_id: 'iot-01', sensor_type: 'iot', co2_ppm: 445.7, temperature_c: 31.2, humidity: 68, region: 'ap-southeast-1', status: 'critical', timestamp: knex.fn.now() },
    { reading_id: 'SR-1007', sensor_id: 'carbon-01', sensor_type: 'carbon_capture', co2_ppm: 398.2, temperature_c: 20.5, humidity: 45, region: 'eu-west-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1008', sensor_id: 'ocean-02', sensor_type: 'oceanographic', co2_ppm: 411.9, temperature_c: 16.8, humidity: 90, region: 'us-west-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1009', sensor_id: 'sat-04', sensor_type: 'satellite', co2_ppm: 425.4, temperature_c: 26.7, humidity: 52, region: 'ap-southeast-1', status: 'normal', timestamp: knex.fn.now() },
    { reading_id: 'SR-1010', sensor_id: 'weather-02', sensor_type: 'weather', co2_ppm: 438.0, temperature_c: 33.4, humidity: 76, region: 'us-east-1', status: 'anomaly', timestamp: knex.fn.now() },
  ])

  await knex('tasks').insert([
    { task_id: 'TASK-201', title: 'Investigate CO2 spike in Asia Pacific', description: 'Sensor readings show critical CO2 levels in ap-southeast-1 region', assignee: 'Jane Manager', priority: 'critical', status: 'in_progress', due_date: knex.fn.now(), created_by: 'Admin User' },
    { task_id: 'TASK-202', title: 'Deploy additional oceanographic sensors', description: 'Expand ocean monitoring coverage in the Pacific corridor', assignee: 'Jane Manager', priority: 'high', status: 'pending', due_date: knex.fn.now(), created_by: 'Admin User' },
    { task_id: 'TASK-203', title: 'Calibrate satellite array sat-03', description: 'Temperature readings from sat-03 showing deviation of 2.1°C', assignee: 'Admin User', priority: 'high', status: 'in_progress', due_date: knex.fn.now(), created_by: 'Admin User' },
    { task_id: 'TASK-204', title: 'Analyze carbon capture efficiency', description: 'Review Q2 carbon capture metrics and optimize capture rates', assignee: 'John Staff', priority: 'medium', status: 'pending', due_date: knex.fn.now(), created_by: 'Jane Manager' },
    { task_id: 'TASK-205', title: 'Update climate simulation models', description: 'Incorporate latest satellite data into predictive climate models', assignee: 'Admin User', priority: 'medium', status: 'completed', due_date: knex.fn.now(), created_by: 'System' },
    { task_id: 'TASK-206', title: 'Verify sensor network redundancy', description: 'Check backup sensor nodes across all climate zones', assignee: 'Mike Johnson', priority: 'low', status: 'pending', due_date: knex.fn.now(), created_by: 'Admin User' },
    { task_id: 'TASK-207', title: 'Review emissions reduction targets', description: 'Compare actual readings against UN carbon reduction goals', assignee: 'Sarah Chen', priority: 'medium', status: 'in_progress', due_date: knex.fn.now(), created_by: 'Jane Manager' },
    { task_id: 'TASK-208', title: 'Approve new carbon credit validation', description: 'Verify carbon credit audit trail for regulatory compliance', assignee: 'Jane Manager', priority: 'high', status: 'pending', due_date: knex.fn.now(), created_by: 'Admin User' },
  ])

  await knex('alerts').insert([
    { alert_id: 'ALT-51', type: 'co2_spike', severity: 'critical', message: 'CO2 concentration exceeded 440ppm threshold in ap-southeast-1', region: 'ap-southeast-1', timestamp: knex.fn.now(), acknowledged: false },
    { alert_id: 'ALT-52', type: 'temperature', severity: 'warning', message: 'Temperature anomaly detected in Pacific sensor cluster', region: 'us-west-1', timestamp: knex.fn.now(), acknowledged: false },
    { alert_id: 'ALT-53', type: 'disk', severity: 'warning', message: 'Climate model data storage running low', region: 'us-east-1', timestamp: knex.fn.now(), acknowledged: true },
    { alert_id: 'ALT-54', type: 'network', severity: 'info', message: 'Satellite uplink latency above normal', region: 'eu-west-1', timestamp: knex.fn.now(), acknowledged: false },
    { alert_id: 'ALT-55', type: 'application', severity: 'warning', message: 'Climate simulation engine response degraded', region: 'us-west-1', timestamp: knex.fn.now(), acknowledged: true },
    { alert_id: 'ALT-56', type: 'security', severity: 'critical', message: 'Unauthorized access attempt on sensor network', region: 'us-east-1', timestamp: knex.fn.now(), acknowledged: false },
    { alert_id: 'ALT-57', type: 'anomaly', severity: 'info', message: 'Unusual weather pattern detected in Atlantic region', region: 'eu-west-1', timestamp: knex.fn.now(), acknowledged: true },
    { alert_id: 'ALT-58', type: 'memory', severity: 'warning', message: 'Climate simulation memory pool exhausted', region: 'ap-southeast-1', timestamp: knex.fn.now(), acknowledged: false },
  ])

  await knex('regions').insert([
    { id: 'us-east-1', name: 'North Atlantic Corridor', status: 'healthy', instances: 24, load_pct: 62, latency_ms: 12 },
    { id: 'us-west-1', name: 'Pacific Northwest Zone', status: 'healthy', instances: 18, load_pct: 45, latency_ms: 18 },
    { id: 'eu-west-1', name: 'European Climate Zone', status: 'healthy', instances: 15, load_pct: 38, latency_ms: 45 },
    { id: 'ap-southeast-1', name: 'Asia Pacific Basin', status: 'degraded', instances: 10, load_pct: 78, latency_ms: 120 },
  ])

  console.log('Database seeded successfully')
}
