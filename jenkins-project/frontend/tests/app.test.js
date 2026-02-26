const { renderStatus, renderResults, renderVoteButtons, formatStorage } = require("../src/app");

describe("frontend helpers", () => {
  it("renders status text into target node", () => {
    document.body.innerHTML = `<p id="status"></p>`;
    const node = document.getElementById("status");

    renderStatus(node, "Backend status: ok");

    expect(node.textContent).toBe("Backend status: ok");
    expect(node.classList.contains("status-error")).toBe(false);
  });

  it("renders voting results", () => {
    document.body.innerHTML = `<ul id="results"></ul>`;
    const node = document.getElementById("results");

    renderResults(node, {
      results: [
        { option: "Engineering", votes: 3 },
        { option: "Product", votes: 1 }
      ],
      totalVotes: 4
    });

    expect(node.textContent).toContain("Engineering");
    expect(node.textContent).toContain("3 vote(s)");
    expect(node.textContent).toContain("75%");
    expect(node.textContent).toContain("Product");
    expect(node.textContent).toContain("1 vote(s)");
    expect(node.textContent).toContain("25%");
  });

  it("renders vote buttons", () => {
    document.body.innerHTML = `<div id="options"></div>`;
    const node = document.getElementById("options");
    const onVote = jest.fn();

    renderVoteButtons(node, ["Engineering", "Design"], onVote);

    const buttons = node.querySelectorAll("button");
    expect(buttons.length).toBe(2);
    expect(buttons[0].textContent).toBe("Engineering");
    buttons[0].click();
    expect(onVote).toHaveBeenCalledWith("Engineering");
  });

  it("formats storage labels", () => {
    expect(formatStorage("redis")).toBe("Redis cache");
    expect(formatStorage("memory")).toBe("in-memory fallback");
  });
});
