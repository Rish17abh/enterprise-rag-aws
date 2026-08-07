(() => {
  const $ = (id) => document.getElementById(id);

  const STORAGE_BASE = "rag_api_base";
  const STORAGE_KEY = "rag_api_key";

  const apiBaseInput = $("apiBase");
  const apiKeyInput = $("apiKey");
  const authPanel = $("authPanel");
  const authBadge = $("authBadge");
  const toggleSettings = $("toggleSettings");
  const credsStatus = $("credsStatus");
  const dropzone = $("dropzone");
  const fileInput = $("fileInput");
  const queue = $("queue");
  const fileName = $("fileName");
  const fileMeta = $("fileMeta");
  const progressBar = $("progressBar");
  const uploadBtn = $("uploadBtn");
  const clearFile = $("clearFile");
  const uploadStatus = $("uploadStatus");
  const uploadDetail = $("uploadDetail");
  const question = $("question");
  const askBtn = $("askBtn");
  const askStatus = $("askStatus");
  const answerBox = $("answerBox");
  const answerText = $("answerText");
  const metrics = $("metrics");

  let selectedFile = null;

  const defaults = {
    ...(window.ENTERPRISE_RAG_CONFIG || {}),
    ...(window.ENTERPRISE_RAG_LOCAL_CONFIG || {}),
  };

  function readStored(key) {
    return localStorage.getItem(key) || sessionStorage.getItem(key) || "";
  }

  function persistCreds(apiBase, apiKey) {
    localStorage.setItem(STORAGE_BASE, apiBase);
    localStorage.setItem(STORAGE_KEY, apiKey);
    sessionStorage.removeItem(STORAGE_BASE);
    sessionStorage.removeItem(STORAGE_KEY);
  }

  function clearStoredCreds() {
    localStorage.removeItem(STORAGE_BASE);
    localStorage.removeItem(STORAGE_KEY);
    sessionStorage.removeItem(STORAGE_BASE);
    sessionStorage.removeItem(STORAGE_KEY);
  }

  function resolveCreds() {
    const apiBase = (
      apiBaseInput.value.trim() ||
      readStored(STORAGE_BASE) ||
      defaults.apiBaseUrl ||
      ""
    ).replace(/\/$/, "");
    const apiKey =
      apiKeyInput.value.trim() ||
      readStored(STORAGE_KEY) ||
      defaults.apiKey ||
      "";
    return { apiBase, apiKey };
  }

  function hasCreds(creds = resolveCreds()) {
    return Boolean(creds.apiBase && creds.apiKey);
  }

  function syncAuthUi(message = "") {
    const ready = hasCreds();
    authBadge.hidden = !ready;
    if (!ready) {
      authPanel.hidden = false;
    }
    if (message) {
      setStatus(credsStatus, message, ready ? "ok" : "bad");
    } else if (ready && !authPanel.hidden) {
      setStatus(credsStatus, "Credentials ready for this browser.", "ok");
    }
  }

  function setStatus(el, message, kind = "") {
    el.textContent = message;
    el.className = `status${kind ? ` ${kind}` : ""}`;
  }

  function getCreds() {
    const creds = resolveCreds();
    if (!creds.apiBase || !creds.apiKey) {
      authPanel.hidden = false;
      throw new Error("Add your API base URL and API key in Settings.");
    }
    // Keep localStorage warm so future sessions stay signed in.
    persistCreds(creds.apiBase, creds.apiKey);
    apiBaseInput.value = creds.apiBase;
    apiKeyInput.value = creds.apiKey;
    syncAuthUi();
    return creds;
  }

  // Seed inputs: stored browser values win, then local serve config, then defaults.
  apiBaseInput.value =
    readStored(STORAGE_BASE) || defaults.apiBaseUrl || "";
  apiKeyInput.value = readStored(STORAGE_KEY) || defaults.apiKey || "";

  // Auto-persist when serve.sh / config.local.js provided a key.
  if (hasCreds()) {
    const seeded = resolveCreds();
    persistCreds(seeded.apiBase, seeded.apiKey);
    authPanel.hidden = true;
    syncAuthUi();
  } else {
    authPanel.hidden = false;
    syncAuthUi("Enter API settings once — they will be remembered.");
  }

  toggleSettings.addEventListener("click", () => {
    authPanel.hidden = !authPanel.hidden;
    if (!authPanel.hidden) {
      apiBaseInput.focus();
    }
  });

  $("saveCreds").addEventListener("click", () => {
    try {
      const apiBase = apiBaseInput.value.trim().replace(/\/$/, "");
      const apiKey = apiKeyInput.value.trim();
      if (!apiBase || !apiKey) {
        throw new Error("API base URL and API key are required.");
      }
      persistCreds(apiBase, apiKey);
      authPanel.hidden = true;
      syncAuthUi("Saved. You will not need to enter these again on this browser.");
    } catch (err) {
      setStatus(credsStatus, err.message, "bad");
    }
  });

  $("clearCreds").addEventListener("click", () => {
    clearStoredCreds();
    apiKeyInput.value = defaults.apiKey || "";
    apiBaseInput.value = defaults.apiBaseUrl || "";
    if (hasCreds()) {
      // Local config still provides values (e.g. serve.sh).
      const seeded = resolveCreds();
      persistCreds(seeded.apiBase, seeded.apiKey);
      syncAuthUi("Browser storage cleared. Local serve config is still active.");
    } else {
      authBadge.hidden = true;
      authPanel.hidden = false;
      setStatus(credsStatus, "Saved credentials cleared.", "warn");
    }
  });

  function acceptFile(file) {
    if (!file) return;
    const lower = file.name.toLowerCase();
    if (!(lower.endsWith(".pdf") || lower.endsWith(".txt"))) {
      setStatus(uploadStatus, "Only .pdf and .txt files are supported.", "bad");
      return;
    }
    selectedFile = file;
    queue.hidden = false;
    fileName.textContent = file.name;
    fileMeta.textContent = `${(file.size / 1024).toFixed(1)} KB · ${file.type || "unknown type"}`;
    progressBar.style.width = "0%";
    uploadDetail.hidden = true;
    setStatus(uploadStatus, "Ready to upload.", "ok");
  }

  dropzone.addEventListener("click", () => fileInput.click());
  dropzone.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      fileInput.click();
    }
  });
  fileInput.addEventListener("change", () => acceptFile(fileInput.files?.[0]));

  ["dragenter", "dragover"].forEach((evt) => {
    dropzone.addEventListener(evt, (e) => {
      e.preventDefault();
      dropzone.classList.add("dragover");
    });
  });
  ["dragleave", "drop"].forEach((evt) => {
    dropzone.addEventListener(evt, (e) => {
      e.preventDefault();
      dropzone.classList.remove("dragover");
    });
  });
  dropzone.addEventListener("drop", (e) => {
    acceptFile(e.dataTransfer?.files?.[0]);
  });

  clearFile.addEventListener("click", () => {
    selectedFile = null;
    fileInput.value = "";
    queue.hidden = true;
    progressBar.style.width = "0%";
    setStatus(uploadStatus, "");
    uploadDetail.hidden = true;
  });

  async function requestPresign(file, apiBase, apiKey) {
    const res = await fetch(`${apiBase}/upload`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
      },
      body: JSON.stringify({
        filename: file.name,
        content_type: file.type || (file.name.toLowerCase().endsWith(".pdf")
          ? "application/pdf"
          : "text/plain"),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(data.error || data.message || `Presign failed (${res.status})`);
    }
    return data;
  }

  function putToS3(uploadUrl, headers, file, onProgress) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open("PUT", uploadUrl);
      Object.entries(headers || {}).forEach(([k, v]) => xhr.setRequestHeader(k, v));
      xhr.upload.onprogress = (evt) => {
        if (!evt.lengthComputable) return;
        onProgress(Math.round((evt.loaded / evt.total) * 100));
      };
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr);
        else reject(new Error(`S3 upload failed (${xhr.status})`));
      };
      xhr.onerror = () => reject(new Error("Network error during S3 upload"));
      xhr.send(file);
    });
  }

  uploadBtn.addEventListener("click", async () => {
    if (!selectedFile) return;
    uploadBtn.disabled = true;
    try {
      const { apiBase, apiKey } = getCreds();
      setStatus(uploadStatus, "Requesting secure upload URL…", "warn");
      progressBar.style.width = "8%";
      const presign = await requestPresign(selectedFile, apiBase, apiKey);
      setStatus(uploadStatus, "Uploading encrypted object to S3…", "warn");
      await putToS3(
        presign.upload_url,
        presign.required_headers,
        selectedFile,
        (pct) => {
          progressBar.style.width = `${Math.max(10, pct)}%`;
        }
      );
      progressBar.style.width = "100%";
      setStatus(
        uploadStatus,
        "Upload complete. Ingestion will redact PII and index vectors shortly.",
        "ok"
      );
      uploadDetail.hidden = false;
      uploadDetail.textContent = JSON.stringify(
        {
          key: presign.key,
          bucket: presign.bucket,
          next_steps: presign.next_steps,
        },
        null,
        2
      );
    } catch (err) {
      progressBar.style.width = "0%";
      setStatus(uploadStatus, err.message || String(err), "bad");
    } finally {
      uploadBtn.disabled = false;
    }
  });

  askBtn.addEventListener("click", async () => {
    askBtn.disabled = true;
    answerBox.hidden = true;
    try {
      const { apiBase, apiKey } = getCreds();
      const q = question.value.trim();
      if (!q) throw new Error("Enter a question first.");
      setStatus(askStatus, "Running retrieval + generation…", "warn");
      const res = await fetch(`${apiBase}/query`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
        },
        body: JSON.stringify({ question: q }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data.error || data.message || data.error_message || `Query failed (${res.status})`);
      }
      answerBox.hidden = false;
      answerText.textContent = data.answer || "(empty answer)";
      const latency = data.latency_ms || {};
      metrics.innerHTML = [
        ["retrieved", data.retrieved_count ?? "—"],
        ["embed ms", latency.embedding ?? "—"],
        ["search ms", latency.retrieval ?? "—"],
        ["llm ms", latency.llm ?? "—"],
        ["total ms", latency.total ?? "—"],
      ]
        .map(([k, v]) => `<div><strong>${k}</strong><br />${v}</div>`)
        .join("");
      setStatus(askStatus, "Done.", "ok");
    } catch (err) {
      setStatus(askStatus, err.message || String(err), "bad");
    } finally {
      askBtn.disabled = false;
    }
  });
})();
