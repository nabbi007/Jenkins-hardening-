const express = require("express");
const client = require("prom-client");
const { redisClient, isRedisConnected } = require("./redis");

const VOTES_KEY = "votes";
const app = express();
const VOTING_QUESTION = "Which team should host the next townhall?";
const VOTING_OPTIONS = ["Engineering", "Product", "Design"];

const registry = new client.Registry();
client.collectDefaultMetrics({ register: registry });

// HTTP Request Metrics
const requestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5], // Better granularity
  registers: [registry]
});

const requestCount = new client.Counter({
  name: "http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "route", "status_code"],
  registers: [registry]
});

const errorCount = new client.Counter({
  name: "http_errors_total",
  help: "Total 4xx and 5xx responses",
  labelNames: ["method", "route", "status_code"],
  registers: [registry]
});

// Business Metrics - Voting
const votesTotal = new client.Counter({
  name: "votes_total",
  help: "Total number of votes cast",
  labelNames: ["option"],
  registers: [registry]
});

const votesGauge = new client.Gauge({
  name: "votes_current",
  help: "Current vote count per option",
  labelNames: ["option"],
  registers: [registry]
});

const totalVotesGauge = new client.Gauge({
  name: "votes_total_count",
  help: "Total number of all votes",
  registers: [registry]
});

// Application Health Metrics
const redisConnectionGauge = new client.Gauge({
  name: "redis_connection_status",
  help: "Redis connection status (1=connected, 0=disconnected)",
  registers: [registry]
});

const activeRequestsGauge = new client.Gauge({
  name: "http_requests_in_progress",
  help: "Number of HTTP requests currently being processed",
  labelNames: ["method", "route"],
  registers: [registry]
});

const pollViewsCounter = new client.Counter({
  name: "poll_views_total",
  help: "Total number of times the poll was viewed",
  registers: [registry]
});

const resultsViewsCounter = new client.Counter({
  name: "results_views_total",
  help: "Total number of times results were viewed",
  registers: [registry]
});

// Update Redis connection status metric
const updateRedisMetric = () => {
  redisConnectionGauge.set(isRedisConnected() ? 1 : 0);
};

// Update vote gauges
const updateVoteMetrics = () => {
  let total = 0;
  VOTING_OPTIONS.forEach(option => {
    const count = voteStore[option] || 0;
    votesGauge.labels(option).set(count);
    total += count;
  });
  totalVotesGauge.set(total);
  updateRedisMetric();
};

app.use(express.json());

const createInitialVotes = () => {
  return Object.fromEntries(VOTING_OPTIONS.map((option) => [option, 0]));
};

let voteStore = createInitialVotes();
const storageMode = () => (isRedisConnected() ? "redis" : "memory");

// Update metrics every 5 seconds (after voteStore is initialized)
const metricsInterval = setInterval(updateVoteMetrics, 5000);
updateVoteMetrics(); // Initial update

const currentResults = () => {
  const results = VOTING_OPTIONS.map((option) => ({
    option,
    votes: voteStore[option]
  }));
  const totalVotes = results.reduce((sum, entry) => sum + entry.votes, 0);

  return {
    question: VOTING_QUESTION,
    results,
    totalVotes,
    storage: storageMode()
  };
};

// Hydrate in-memory store from Redis on startup so votes survive restarts.
const hydrateVotes = async () => {
  if (!isRedisConnected()) return;
  try {
    const raw = await redisClient.hgetall(VOTES_KEY);
    if (raw) {
      for (const option of VOTING_OPTIONS) {
        if (raw[option] !== undefined) {
          voteStore[option] = parseInt(raw[option], 10) || 0;
        }
      }
      console.log("Vote store hydrated from Redis", voteStore);
    }
  } catch (err) {
    console.warn("Could not hydrate votes from Redis:", err.message);
  }
};

// Persist a single vote increment to Redis (fire-and-forget, non-blocking).
const persistVoteToRedis = (option) => {
  if (!isRedisConnected()) return;
  redisClient.hincrby(VOTES_KEY, option, 1).catch((err) =>
    console.warn("Redis vote persist failed:", err.message)
  );
};

const resetVotes = async () => {
  voteStore = createInitialVotes();
  if (!isRedisConnected()) return;
  try {
    await redisClient.hset(
      VOTES_KEY,
      Object.fromEntries(VOTING_OPTIONS.map((o) => [o, 0]))
    );
  } catch (err) {
    console.warn("Redis reset failed:", err.message);
  }
};

// Hydrate when Redis connects (or immediately if already connected).
redisClient.on("connect", () => {
  hydrateVotes();
});

// Attempt an immediate hydrate as well.
hydrateVotes();

app.use((req, res, next) => {
  const startNs = process.hrtime.bigint();
  const route = req.route?.path || req.path || "unknown";
  
  // Track in-progress requests
  activeRequestsGauge.labels(req.method, route).inc();

  res.on("finish", () => {
    const durationSeconds = Number(process.hrtime.bigint() - startNs) / 1e9;
    const statusCode = String(res.statusCode);

    // Record metrics
    requestDuration.labels(req.method, route, statusCode).observe(durationSeconds);
    requestCount.labels(req.method, route, statusCode).inc();

    if (res.statusCode >= 400) {
      errorCount.labels(req.method, route, statusCode).inc();
    }

    // Decrement in-progress requests
    activeRequestsGauge.labels(req.method, route).dec();
  });

  next();
});

app.get("/api/health", (_req, res) => {
  res.status(200).json({
    status: "ok",
    service: "backend",
    storage: storageMode(),
    timestamp: new Date().toISOString()
  });
});

app.get("/api/poll", (_req, res) => {
  pollViewsCounter.inc();
  res.status(200).json({
    question: VOTING_QUESTION,
    options: VOTING_OPTIONS
  });
});

app.post("/api/vote", (req, res) => {
  const option = req.body?.option;

  if (!option || !VOTING_OPTIONS.includes(option)) {
    return res.status(400).json({
      error: "Invalid option",
      options: VOTING_OPTIONS
    });
  }

  voteStore[option] += 1;
  persistVoteToRedis(option);
  
  // Track business metrics
  votesTotal.labels(option).inc();
  updateVoteMetrics(); // Immediate update

  return res.status(200).json({
    message: "Vote accepted",
    selectedOption: option,
    ...currentResults()
  });
});

app.get("/api/results", (_req, res) => {
  resultsViewsCounter.inc();
  res.status(200).json(currentResults());
});

app.get("/api/fail", (_req, res) => {
  res.status(500).json({ error: "Forced failure for alert testing" });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", registry.contentType);
  res.send(await registry.metrics());
});

app.use((_req, res) => {
  res.status(404).json({ error: "Not found" });
});

module.exports = {
  app,
  resetVotes,
  metricsInterval
};
