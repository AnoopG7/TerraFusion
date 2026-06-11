import client from 'prom-client'
import { Request, Response, NextFunction } from 'express'

const register = new client.Registry()

client.collectDefaultMetrics({ register })

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'path', 'status'],
  registers: [register],
})

const sensorCo2Ppm = new client.Gauge({
  name: 'terrafusion_sensor_co2_ppm',
  help: 'Latest CO2 PPM sensor reading',
  registers: [register],
})

const sensorTemperatureC = new client.Gauge({
  name: 'terrafusion_sensor_temperature_c',
  help: 'Latest temperature in Celsius sensor reading',
  registers: [register],
})

export function trackRequest(req: Request, res: Response, next: NextFunction) {
  res.on('finish', () => {
    httpRequestsTotal.inc({ method: req.method, path: req.route?.path || req.path, status: res.statusCode })
  })
  next()
}

export function updateSensorGauges(co2Ppm: number, temperatureC: number) {
  sensorCo2Ppm.set(co2Ppm)
  sensorTemperatureC.set(temperatureC)
}

export async function metricsHandler(_req: Request, res: Response) {
  res.set('Content-Type', register.contentType)
  res.send(await register.metrics())
}

export { register }
