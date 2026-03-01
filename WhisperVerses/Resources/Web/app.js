// WhisperVerses Follow-Along Client

class ManuscriptFollower {
    constructor() {
        this.ws = null;
        this.currentPosition = -1;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 1000;
        this.isSessionOwner = false;

        this.container = document.getElementById('container');
        this.manuscriptScroll = document.getElementById('manuscriptScroll');
        this.manuscriptContent = document.getElementById('manuscriptContent');
        this.connectionStatus = document.getElementById('connectionStatus');
        this.offScriptWarning = document.getElementById('offScriptWarning');
        this.filenameEl = document.getElementById('filename');
        this.clipButton = document.getElementById('clipButton');

        // Store chunk elements for scroll positioning
        this.chunkElements = [];
        this.manuscriptRendered = false;

        this.init();
    }

    init() {
        // Check for manuscript in session storage (uploaders have this)
        const manuscriptText = sessionStorage.getItem('manuscriptText');
        const filename = sessionStorage.getItem('manuscriptFilename');

        if (filename) {
            this.filenameEl.textContent = filename;
        }

        // Connect to WebSocket - we'll either send manuscript or just listen
        this.connect(manuscriptText, filename);
        this.setupEventListeners();
    }

    connect(manuscriptText = null, filename = null) {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;

        this.ws = new WebSocket(wsUrl);

        this.ws.onopen = () => {
            console.log('WebSocket connected');
            this.reconnectAttempts = 0;
            this.updateConnectionStatus(true);

            // Send manuscript if we have one (we're the uploader)
            if (manuscriptText) {
                const message = JSON.stringify({
                    type: 'manuscript',
                    content: manuscriptText,
                    filename: filename || 'Unknown'
                });
                this.ws.send(message);
                this.isSessionOwner = true;
            }
            // Otherwise we're joining an existing session - server will send current state
        };

        this.ws.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                this.handleUpdate(data);
            } catch (e) {
                console.error('Failed to parse WebSocket message:', e);
            }
        };

        this.ws.onclose = () => {
            this.updateConnectionStatus(false);
            this.attemptReconnect();
        };

        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }

    attemptReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            const delay = this.reconnectDelay * Math.pow(1.5, this.reconnectAttempts - 1);
            this.connectionStatus.textContent = `Reconnecting (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`;
            setTimeout(() => this.connect(), delay);
        } else {
            this.connectionStatus.textContent = 'Connection failed';
        }
    }

    updateConnectionStatus(connected) {
        if (connected) {
            this.connectionStatus.textContent = 'Connected';
            this.connectionStatus.classList.add('connected');
            this.connectionStatus.classList.remove('disconnected');
        } else {
            this.connectionStatus.textContent = 'Disconnected';
            this.connectionStatus.classList.add('disconnected');
            this.connectionStatus.classList.remove('connected');
        }
    }

    handleUpdate(data) {
        // Handle session ended
        if (data.type === 'sessionEnded') {
            sessionStorage.removeItem('manuscriptText');
            sessionStorage.removeItem('manuscriptFilename');
            window.location.href = '/';
            return;
        }

        // Handle errors (e.g., session already active)
        if (data.type === 'error') {
            console.warn('Server error:', data.message);
            if (data.filename) {
                this.filenameEl.textContent = data.filename;
            }
            // Don't redirect - we can still view the existing session
            return;
        }

        // Update off-script state
        if (data.isOffScript) {
            this.container.classList.add('off-script');
            this.offScriptWarning.classList.add('visible');
        } else {
            this.container.classList.remove('off-script');
            this.offScriptWarning.classList.remove('visible');
        }

        // Render chunks if we have them
        if (data.chunks && data.chunks.length > 0) {
            this.renderManuscript(data.chunks, data.currentPosition, data.matchedWords || {});
        }
    }

    renderManuscript(chunks, currentPosition, matchedWords = {}) {
        // Render the manuscript (only once)
        if (!this.manuscriptRendered) {
            this.manuscriptContent.innerHTML = '';
            this.chunkElements = [];

            chunks.forEach((chunk, idx) => {
                const chunkEl = document.createElement('div');
                chunkEl.className = 'chunk-section ' + chunk.status;
                chunkEl.dataset.id = chunk.id;

                // Split chunk text into paragraphs
                const text = chunk.text;
                const paragraphs = text.includes('\n\n')
                    ? text.split(/\n\n+/)
                    : text.split(/\n/);

                paragraphs.forEach(para => {
                    const trimmed = para.trim();
                    if (trimmed) {
                        const p = document.createElement('p');
                        p.textContent = trimmed;
                        chunkEl.appendChild(p);
                    }
                });

                this.manuscriptContent.appendChild(chunkEl);
                this.chunkElements.push(chunkEl);
            });

            this.manuscriptRendered = true;
        } else {
            // Update chunk statuses
            chunks.forEach((chunk, idx) => {
                if (this.chunkElements[idx]) {
                    this.chunkElements[idx].className = 'chunk-section ' + chunk.status;
                }
            });
        }

        // Highlight matched words in chunks
        this.highlightMatchedWords(matchedWords);

        // Scroll to current position if changed
        if (this.currentPosition !== currentPosition) {
            this.currentPosition = currentPosition;
            this.scrollToCurrentChunk();
        }
    }

    highlightMatchedWords(matchedWords) {
        // Clear previous highlights
        this.chunkElements.forEach(chunkEl => {
            const paragraphs = chunkEl.querySelectorAll('p');
            paragraphs.forEach(p => {
                if (p.querySelector('.matched')) {
                    // Restore original text
                    p.textContent = p.textContent;
                }
            });
        });

        // Apply new highlights
        for (const [chunkIdxStr, words] of Object.entries(matchedWords)) {
            const chunkIdx = parseInt(chunkIdxStr);
            const chunkEl = this.chunkElements[chunkIdx];
            if (!chunkEl) continue;

            // Create a set of lowercase matched words for quick lookup
            const matchedSet = new Set(words.map(w => w.toLowerCase()));

            // Process each paragraph in the chunk
            const paragraphs = chunkEl.querySelectorAll('p');
            paragraphs.forEach(p => {
                const originalText = p.textContent;
                // Split into words while preserving delimiters
                const parts = originalText.split(/(\s+|[.,!?;:'"()-]+)/);

                let hasMatches = false;
                const html = parts.map(part => {
                    // Normalize the word for comparison
                    const normalized = part.toLowerCase().replace(/[^a-z]/g, '');
                    // Allow any length word to be highlighted if it's in the matched set
                    // (gap-filling includes short words like "to", "a", "in")
                    if (normalized.length >= 1 && matchedSet.has(normalized)) {
                        hasMatches = true;
                        return `<span class="matched">${this.escapeHtml(part)}</span>`;
                    }
                    return this.escapeHtml(part);
                }).join('');

                if (hasMatches) {
                    p.innerHTML = html;
                }
            });
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    scrollToCurrentChunk() {
        if (this.currentPosition < 0 || this.currentPosition >= this.chunkElements.length) {
            return;
        }

        const chunkEl = this.chunkElements[this.currentPosition];
        if (!chunkEl) return;

        // Scroll so current chunk is near the top of the viewport
        const scrollContainer = this.manuscriptScroll;
        const containerRect = scrollContainer.getBoundingClientRect();
        const chunkRect = chunkEl.getBoundingClientRect();

        // Calculate where chunk currently is relative to container
        const chunkTopInContainer = chunkRect.top - containerRect.top + scrollContainer.scrollTop;

        // Scroll to put chunk near top with some padding
        const targetScroll = chunkTopInContainer - 20;

        scrollContainer.scrollTo({
            top: Math.max(0, targetScroll),
            behavior: 'smooth'
        });
    }

    setupEventListeners() {
        // Clip button
        this.clipButton.addEventListener('click', () => this.sendClip());

        // Keyboard shortcut for clip (C key)
        document.addEventListener('keydown', (e) => {
            if (e.key.toLowerCase() === 'c' && !e.ctrlKey && !e.metaKey && !e.altKey) {
                if (e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
                    this.sendClip();
                }
            }
        });

        // Handle window resize
        window.addEventListener('resize', () => {
            if (this.currentPosition >= 0) {
                this.scrollToCurrentChunk();
            }
        });
    }

    sendClip() {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ type: 'clip' }));

            // Visual feedback
            this.clipButton.style.transform = 'scale(0.95)';
            this.clipButton.style.background = '#4caf50';

            setTimeout(() => {
                this.clipButton.style.transform = '';
                this.clipButton.style.background = '';
            }, 200);
        }
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new ManuscriptFollower();
});
