(() => {
  const $ = (id) => document.getElementById(id);

  const apiBaseInput = $("apiBase");
  const apiKeyInput = $("apiKey");
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

  const defaults = window.ENTERPRISE_RAG_CONFIG || {};
  apiBaseInput.value =
    sessionStorage.getItem("rag_api_base") || defaults.apiBaseUrl || "";
  apiKeyInput.value = sessionStorage.getItem("rag_api_key") || "";

  function setStatus(el, message, kind = "") {
    el.textContent = message;
    el.className = `status${kind ? ` ${kind}` : ""}`;
  }

  function getCreds() {
    const apiBase = apiBaseInput.value.trim().replace(/\/$/, "");
    const apiKey = apiKeyInput.value.trim();
    if (!apiBase || !apiKey) {
      throw new Error("Save your API base URL and API key first.");
    }
    return { apiBase, apiKey };
  }

  $("saveCreds").addEventListener("click", () => {
    try {
      const { apiBase, apiKey } = getCreds();
      sessionStorage.setItem("rag_api_base", apiBase);
      sessionStorage.setItem("rag_api_key", apiKey);
      setStatus(credsStatus, "Session credentials saved.", "ok");
    } catch (err) {
      setStatus(credsStatus, err.message, "bad");
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
        "Upload complete. Ingestion pipeline will redact PII and index vectors shortly.",
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
