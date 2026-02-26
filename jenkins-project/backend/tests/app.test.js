const request = require("supertest");

// Mock Redis before importing app so no real Redis connection is attempted.
// isRedisConnected returns false -> all operations stay in-memory.
jest.mock("../src/redis", () => ({
  redisClient: {
    hgetall: jest.fn().mockResolvedValue(null),
    hset: jest.fn().mockResolvedValue("OK"),
    hincrby: jest.fn().mockResolvedValue(1),
    on: jest.fn()
  },
  isRedisConnected: jest.fn().mockReturnValue(false)
}));

const { app, resetVotes, metricsInterval } = require("../src/app");

describe("backend service", () => {
  beforeEach(async () => {
    await resetVotes();
  });

  afterAll(() => {
    // Clean up the metrics interval to allow Jest to exit
    if (metricsInterval) {
      clearInterval(metricsInterval);
    }
  });

  it("returns health payload", async () => {
    const response = await request(app).get("/api/health");

    expect(response.statusCode).toBe(200);
    expect(response.body.status).toBe("ok");
    expect(response.body.service).toBe("backend");
  });

  it("returns poll metadata", async () => {
    const response = await request(app).get("/api/poll");

    expect(response.statusCode).toBe(200);
    expect(response.body.question).toBeTruthy();
    expect(Array.isArray(response.body.options)).toBe(true);
    expect(response.body.options.length).toBeGreaterThan(0);
  });

  it("accepts a vote and updates results", async () => {
    const pollResponse = await request(app).get("/api/poll");
    const selectedOption = pollResponse.body.options[0];

    const voteResponse = await request(app)
      .post("/api/vote")
      .send({ option: selectedOption });

    expect(voteResponse.statusCode).toBe(200);
    expect(voteResponse.body.selectedOption).toBe(selectedOption);
    expect(voteResponse.body.totalVotes).toBe(1);
    expect(voteResponse.body.results.find((entry) => entry.option === selectedOption).votes).toBe(1);
  });

  it("rejects an invalid vote option", async () => {
    const response = await request(app)
      .post("/api/vote")
      .send({ option: "Unknown Team" });

    expect(response.statusCode).toBe(400);
    expect(response.body.error).toBe("Invalid option");
  });

  it("returns current results", async () => {
    const pollResponse = await request(app).get("/api/poll");
    const selectedOption = pollResponse.body.options[1];

    await request(app)
      .post("/api/vote")
      .send({ option: selectedOption });

    const resultsResponse = await request(app).get("/api/results");

    expect(resultsResponse.statusCode).toBe(200);
    expect(resultsResponse.body.totalVotes).toBe(1);
    expect(resultsResponse.body.results.find((entry) => entry.option === selectedOption).votes).toBe(1);
  });

  it("exposes Prometheus metrics", async () => {
    await request(app).get("/api/health");
    const response = await request(app).get("/metrics");

    expect(response.statusCode).toBe(200);
    expect(response.text).toContain("http_requests_total");
  });

  it("returns 500 for fail endpoint", async () => {
    const response = await request(app).get("/api/fail");

    expect(response.statusCode).toBe(500);
  });

  it("returns 404 for unknown route", async () => {
    const response = await request(app).get("/api/does-not-exist");

    expect(response.statusCode).toBe(404);
  });
});
