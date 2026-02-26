const Redis = require("ioredis");

const REDIS_URL = process.env.REDIS_URL || "redis://localhost:6379";

const redisClient = new Redis(REDIS_URL, {
  lazyConnect: true,
  connectTimeout: 3000,
  maxRetriesPerRequest: 1,
  enableOfflineQueue: false
});

let redisConnected = false;

redisClient.on("connect", () => {
  redisConnected = true;
  console.log("Redis connected");
});

redisClient.on("error", (err) => {
  redisConnected = false;
  console.warn("Redis unavailable, using in-memory fallback:", err.message);
});

redisClient.connect().catch(() => {});

const isRedisConnected = () => redisConnected;

module.exports = { redisClient, isRedisConnected };
