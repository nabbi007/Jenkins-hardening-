function renderStatus(target, payload, isError = false) {
  target.textContent = payload;
  target.classList.toggle("status-error", isError);
}

function formatStorage(storage) {
  if (storage === "redis") return "Redis cache";
  return "in-memory fallback";
}

function renderResults(target, payload) {
  const totalVotes = Math.max(payload.totalVotes || 0, 1);
  target.innerHTML = payload.results
    .map((entry) => {
      const percent = Math.round((entry.votes / totalVotes) * 100);
      return `
        <li class="result-row">
          <div class="result-head">
            <strong>${entry.option}</strong>
            <span>${entry.votes} vote(s) • ${percent}%</span>
          </div>
          <div class="bar-track">
            <div class="bar-fill" style="width: ${percent}%"></div>
          </div>
        </li>
      `;
    })
    .join("");
}

function renderVoteButtons(target, options, onVote) {
  target.innerHTML = "";
  options.forEach((option) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "vote-btn";
    button.textContent = option;
    button.addEventListener("click", () => onVote(option));
    target.appendChild(button);
  });
}

function setLoadingState(button, isLoading, label = "Refresh Results") {
  button.disabled = isLoading;
  button.textContent = isLoading ? label : "Refresh Results";
}

function updateLastUpdated(node) {
  node.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
}

async function requestJson(baseUrl, path, init = undefined) {
  const response = await fetch(`${baseUrl}${path}`, {
    cache: "no-store",
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.headers || {})
    }
  });
  if (!response.ok) {
    throw new Error(`Request failed with ${response.status}`);
  }
  return response.json();
}

async function loadPoll(baseUrl) {
  return requestJson(baseUrl, "/api/poll");
}

async function loadResults(baseUrl) {
  return requestJson(baseUrl, "/api/results");
}

async function submitVote(baseUrl, option) {
  return requestJson(baseUrl, "/api/vote", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ option })
  });
}

async function refreshResults(context) {
  const payload = await loadResults(context.apiBase);
  renderResults(context.resultsNode, payload);
  renderStatus(
    context.statusNode,
    `Total votes: ${payload.totalVotes}. Storage: ${formatStorage(payload.storage)}.`,
    false
  );
  updateLastUpdated(context.lastUpdatedNode);
  return payload;
}

async function loadPollAndRenderOptions(context) {
  const poll = await loadPoll(context.apiBase);
  context.questionNode.textContent = poll.question;
  renderVoteButtons(context.optionsNode, poll.options, async (option) => {
    try {
      setLoadingState(context.refreshButton, true, "Submitting...");
      await submitVote(context.apiBase, option);
      await refreshResults(context);
    } catch (error) {
      renderStatus(context.statusNode, `Vote failed: ${error.message}`, true);
    } finally {
      setLoadingState(context.refreshButton, false);
    }
  });
}

async function syncView(context) {
  await loadPollAndRenderOptions(context);
  await refreshResults(context);
}

async function handleManualRefresh(context) {
  try {
    setLoadingState(context.refreshButton, true, "Refreshing...");
    await syncView(context);
  } catch (error) {
    renderStatus(context.statusNode, `Backend unavailable: ${error.message}`, true);
  } finally {
    setLoadingState(context.refreshButton, false);
  }
}

function initializeVotingApp() {
  const statusNode = document.getElementById("status");
  const questionNode = document.getElementById("question");
  const optionsNode = document.getElementById("options");
  const resultsNode = document.getElementById("results");
  const refreshButton = document.getElementById("refresh");
  const lastUpdatedNode = document.getElementById("last-updated");
  const apiBase = window.APP_BACKEND_URL || "";

  if (!statusNode || !questionNode || !optionsNode || !resultsNode || !refreshButton || !lastUpdatedNode) {
    return;
  }

  const context = {
    apiBase,
    statusNode,
    questionNode,
    optionsNode,
    resultsNode,
    refreshButton,
    lastUpdatedNode
  };

  refreshButton.addEventListener("click", async () => {
    await handleManualRefresh(context);
  });

  handleManualRefresh(context);

  setInterval(() => {
    refreshResults(context).catch(() => {});
  }, 15000);
}

if (typeof window !== "undefined") {
  window.addEventListener("DOMContentLoaded", initializeVotingApp);
}

if (typeof module !== "undefined") {
  module.exports = {
    renderStatus,
    renderResults,
    renderVoteButtons,
    formatStorage
  };
}
