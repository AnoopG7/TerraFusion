import { faker } from '@faker-js/faker'

let readingCounter = 1000
let taskCounter = 200
let alertCounter = 50

export function generateReading() {
  return {
    id: `SR-${++readingCounter}`,
    sensorId: faker.helpers.arrayElement(['sat-01', 'sat-02', 'ocean-01', 'ocean-02', 'weather-01', 'weather-02', 'iot-01', 'carbon-01']),
    sensorType: faker.helpers.arrayElement(['satellite', 'oceanographic', 'weather', 'iot', 'carbon_capture']),
    co2Ppm: parseFloat(faker.finance.amount({ min: 390, max: 460 })),
    temperatureC: parseFloat(faker.finance.amount({ min: 15, max: 38 })),
    humidity: parseFloat(faker.finance.amount({ min: 30, max: 95 })),
    region: faker.helpers.arrayElement(['us-east-1', 'us-west-1', 'eu-west-1', 'ap-southeast-1']),
    status: faker.helpers.arrayElement(['normal', 'normal', 'normal', 'anomaly', 'critical']),
    timestamp: faker.date.recent({ days: 7 }),
  }
}

export function generateKPIs() {
  return {
    totalReadings: faker.number.int({ min: 15000, max: 50000 }),
    dataAccuracy: faker.number.float({ min: 95, max: 99.9, fractionDigits: 1 }),
    activeSensors: faker.number.int({ min: 36, max: 72 }),
    carbonCaptured: faker.number.float({ min: 395, max: 445, fractionDigits: 1 }),
    systemUptime: faker.number.float({ min: 99.5, max: 99.99, fractionDigits: 2 }),
    avgLatency: faker.number.int({ min: 45, max: 250 }),
    readingsToday: faker.number.int({ min: 500, max: 3000 }),
    activeZones: 4,
  }
}

export function generateSystemMetrics() {
  return {
    cpu: faker.number.float({ min: 15, max: 95, fractionDigits: 1 }),
    memory: faker.number.float({ min: 30, max: 92, fractionDigits: 1 }),
    disk: faker.number.float({ min: 25, max: 88, fractionDigits: 1 }),
    networkIn: faker.number.float({ min: 50, max: 950, fractionDigits: 1 }),
    networkOut: faker.number.float({ min: 20, max: 600, fractionDigits: 1 }),
    dbConnections: faker.number.int({ min: 12, max: 85 }),
    requestsPerMin: faker.number.int({ min: 200, max: 3500 }),
  }
}

export function generateTask() {
  return {
    id: `TASK-${++taskCounter}`,
    title: faker.helpers.arrayElement([
      'Investigate CO2 spike in Asia Pacific',
      'Deploy additional oceanographic sensors',
      'Calibrate satellite array sat-03',
      'Analyze carbon capture efficiency',
      'Update climate simulation models',
      'Verify sensor network redundancy',
      'Review emissions reduction targets',
      'Approve new carbon credit validation',
    ]),
    description: faker.lorem.sentence(),
    assignee: faker.person.fullName(),
    priority: faker.helpers.arrayElement(['low', 'medium', 'high', 'critical']),
    status: faker.helpers.arrayElement(['pending', 'in_progress', 'completed']),
    dueDate: faker.date.soon({ days: 14 }),
    createdBy: faker.person.fullName(),
  }
}

export function generateAlert() {
  return {
    id: `ALT-${++alertCounter}`,
    type: faker.helpers.arrayElement(['cpu', 'memory', 'disk', 'network', 'application', 'security', 'co2_spike', 'temperature', 'anomaly']),
    severity: faker.helpers.arrayElement(['info', 'warning', 'critical']),
    message: faker.helpers.arrayElement([
      'CO2 concentration exceeded 440ppm threshold',
      'Temperature anomaly detected in sensor cluster',
      'Climate model data storage running low',
      'Satellite uplink latency above normal',
      'Climate simulation engine response degraded',
      'Unauthorized access attempt on sensor network',
      'Unusual weather pattern detected',
      'Climate simulation memory pool exhausted',
    ]),
    region: faker.helpers.arrayElement(['us-east-1', 'us-west-1', 'eu-west-1', 'ap-southeast-1']),
    timestamp: faker.date.recent({ days: 2 }),
    acknowledged: faker.datatype.boolean(0.4),
  }
}

export function generateReadings(count = 20) {
  return Array.from({ length: count }, generateReading)
}

export function generateTasks(count = 10) {
  return Array.from({ length: count }, generateTask)
}

export function generateAlerts(count = 8) {
  return Array.from({ length: count }, generateAlert)
}

export function generateTimeSeriesData(points = 24) {
  return Array.from({ length: points }, (_, i) => ({
    time: `${String(i).padStart(2, '0')}:00`,
    value: faker.number.float({ min: 30, max: 95, fractionDigits: 1 }),
  }))
}

export const REGIONS = [
  { id: 'us-east-1', name: 'North Atlantic Corridor', status: 'healthy', instances: 24, load: 62, latency: 12 },
  { id: 'us-west-1', name: 'Pacific Northwest Zone', status: 'healthy', instances: 18, load: 45, latency: 18 },
  { id: 'eu-west-1', name: 'European Climate Zone', status: 'healthy', instances: 15, load: 38, latency: 45 },
  { id: 'ap-southeast-1', name: 'Asia Pacific Basin', status: 'degraded', instances: 10, load: 78, latency: 120 },
]

export const PRICING_DATA = {
  compute: [
    { tier: 'Bronze', instance: 't3.medium', vCPU: 2, memory: '4 GB', monthly: 30.0, hourly: 0.0416, sla: '99.9%' },
    { tier: 'Silver', instance: 't3.large', vCPU: 2, memory: '8 GB', monthly: 60.0, hourly: 0.0832, sla: '99.95%' },
    { tier: 'Gold', instance: 'm5.large', vCPU: 2, memory: '8 GB', monthly: 70.0, hourly: 0.096, sla: '99.99%' },
    { tier: 'Platinum', instance: 'm5.xlarge', vCPU: 4, memory: '16 GB', monthly: 140.0, hourly: 0.192, sla: '99.995%' },
  ],
  storage: [
    { tier: 'Standard', type: 'gp3', pricePerGB: 0.08, iops: 3000, throughput: '125 MB/s' },
    { tier: 'Performance', type: 'io2', pricePerGB: 0.125, iops: 10000, throughput: '500 MB/s' },
  ],
  network: {
    intraRegion: 0.01,
    crossRegion: 0.02,
    internet: 0.09,
  },
  backup: {
    standard: { monthly: 0.05, retention: '30 days', rpo: '1 hour', rto: '4 hours' },
    enhanced: { monthly: 0.10, retention: '90 days', rpo: '5 minutes', rto: '1 hour' },
    premium: { monthly: 0.20, retention: '365 days', rpo: '1 minute', rto: '15 minutes' },
  },
  monitoring: [
    { tier: 'Basic', metrics: '10', retention: '7 days', alerts: '5', monthly: 15 },
    { tier: 'Standard', metrics: '25', retention: '30 days', alerts: '20', monthly: 45 },
    { tier: 'Enterprise', metrics: 'Unlimited', retention: '90 days', alerts: 'Unlimited', monthly: 100 },
  ],
}
