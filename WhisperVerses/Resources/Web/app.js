// WhisperVerses Follow-Along Client

class ManuscriptFollower {
    constructor() {
        this.ws = null;
        this.currentPosition = -1;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 1000;

        this.container = document.getElementById('container');
        this.manuscriptView = document.getElementById('manuscriptView');
        this.connectionStatus = document.getElementById('connectionStatus');
        this.offScriptWarning = document.getElementById('offScriptWarning');
        this.filenameEl = document.getElementById('filename');
        this.clipButton = document.getElementById('clipButton');

        this.init();
    }

    init() {
        // Check for manuscript in session storage
        const manuscriptText = sessionStorage.getItem('manuscriptText');
        const filename = sessionStorage.getItem('manuscriptFilename');

        if (!manuscriptText) {
            window.location.href = '/';
            return;
        }

        if (filename) {
            this.filenameEl.textContent = filename;
        }

        this.connect();
        this.setupEventListeners();
    }

    connect() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;

        this.ws = new WebSocket(wsUrl);

        this.ws.onopen = () => {
            this.reconnectAttempts = 0;
            this.updateConnectionStatus(true);

            // Send manuscript
            const manuscriptText = sessionStorage.getItem('manuscriptText');
            if (manuscriptText) {
                this.ws.send(JSON.stringify({
                    type: 'manuscript',
                    content: manuscriptText
                }));
            }
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
        // Update off-script state
        if (data.isOffScript) {
            this.container.classList.add('off-script');
            this.offScriptWarning.classList.add('visible');
        } else {
            this.container.classList.remove('off-script');
            this.offScriptWarning.classList.remove('visible');
        }

        // Render chunks
        if (data.chunks && data.chunks.length > 0) {
            this.renderChunks(data.chunks, data.currentPosition);
        }
    }

    renderChunks(chunks, currentPosition) {
        // Only re-render if position changed or first render
        if (this.currentPosition === currentPosition && this.manuscriptView.children.length > 1) {
            // Just update classes
            const chunkElements = this.manuscriptView.querySelectorAll('.chunk');
            chunkElements.forEach((el, idx) => {
                el.className = 'chunk ' + chunks[idx].status;
            });
        } else {
            // Full re-render
            this.manuscriptView.innerHTML = chunks.map((chunk, idx) =>
                `<div class="chunk ${chunk.status}" data-id="${chunk.id}">${this.escapeHtml(chunk.text)}</div>`
            ).join('');

            this.currentPosition = currentPosition;

            // Scroll to current chunk
            this.scrollToCurrentChunk();
        }
    }

    scrollToCurrentChunk() {
        const currentChunk = this.manuscriptView.querySelector('.chunk.current');
        if (currentChunk) {
            currentChunk.scrollIntoView({
                behavior: 'smooth',
                block: 'center'
            });
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    setupEventListeners() {
        // Clip button
        this.clipButton.addEventListener('click', () => this.sendClip());

        // Keyboard shortcut for clip (C key)
        document.addEventListener('keydown', (e) => {
            if (e.key.toLowerCase() === 'c' && !e.ctrlKey && !e.metaKey && !e.altKey) {
                // Don't trigger if user is typing in an input
                if (e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
                    this.sendClip();
                }
            }
        });

        // Clear session on page unload
        window.addEventListener('beforeunload', () => {
            if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                this.ws.send(JSON.stringify({ type: 'reset' }));
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
