/**
 * N8N AI Starter Kit - Web Interface JavaScript
 * Main JavaScript functionality for the web interface
 */

// Global configuration
const CONFIG = {
    apiBaseUrl: window.location.origin,
    refreshInterval: 30000, // 30 seconds
    animationDuration: 300,
    maxRetries: 3
};

// Utility functions
const Utils = {
    /**
     * Format date to local string
     * @param {string|Date} date - Date to format
     * @returns {string} Formatted date string
     */
    formatDate(date) {
        if (!date) return '-';
        return new Date(date).toLocaleDateString();
    },

    /**
     * Format date and time to local string
     * @param {string|Date} date - Date to format
     * @returns {string} Formatted datetime string
     */
    formatDateTime(date) {
        if (!date) return '-';
        return new Date(date).toLocaleString();
    },

    /**
     * Format duration from milliseconds
     * @param {number} ms - Duration in milliseconds
     * @returns {string} Formatted duration
     */
    formatDuration(ms) {
        if (!ms) return '-';
        if (ms < 1000) return `${ms}ms`;
        if (ms < 60000) return `${Math.round(ms / 1000)}s`;
        return `${Math.round(ms / 60000)}m`;
    },

    /**
     * Debounce function calls
     * @param {Function} func - Function to debounce
     * @param {number} wait - Wait time in milliseconds
     * @returns {Function} Debounced function
     */
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    },

    /**
     * Show loading spinner
     * @param {HTMLElement} element - Element to show spinner in
     */
    showLoading(element) {
        element.innerHTML = `
            <div class="text-center">
                <div class="spinner-border" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
            </div>
        `;
    },

    /**
     * Show error message
     * @param {HTMLElement} element - Element to show error in
     * @param {string} message - Error message
     */
    showError(element, message = 'An error occurred') {
        element.innerHTML = `
            <div class="alert alert-danger">
                <i class="fas fa-exclamation-triangle"></i> ${message}
            </div>
        `;
    },

    /**
     * Show success message
     * @param {string} message - Success message
     */
    showSuccess(message) {
        this.showToast(message, 'success');
    },

    /**
     * Show toast notification
     * @param {string} message - Toast message
     * @param {string} type - Toast type (success, error, warning, info)
     */
    showToast(message, type = 'info') {
        const toastContainer = this.getToastContainer();
        const toast = document.createElement('div');
        toast.className = `toast align-items-center text-white bg-${type} border-0`;
        toast.setAttribute('role', 'alert');
        toast.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">${message}</div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        `;
        
        toastContainer.appendChild(toast);
        const bsToast = new bootstrap.Toast(toast);
        bsToast.show();
        
        // Remove toast after it's hidden
        toast.addEventListener('hidden.bs.toast', () => {
            toast.remove();
        });
    },

    /**
     * Get or create toast container
     * @returns {HTMLElement} Toast container element
     */
    getToastContainer() {
        let container = document.getElementById('toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'toast-container';
            container.className = 'toast-container position-fixed top-0 end-0 p-3';
            document.body.appendChild(container);
        }
        return container;
    }
};

// API client
const API = {
    /**
     * Make API request with retry logic
     * @param {string} endpoint - API endpoint
     * @param {Object} options - Fetch options
     * @returns {Promise} API response
     */
    async request(endpoint, options = {}) {
        const url = `${CONFIG.apiBaseUrl}${endpoint}`;
        const defaultOptions = {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            }
        };

        let lastError;
        for (let i = 0; i < CONFIG.maxRetries; i++) {
            try {
                const response = await fetch(url, { ...defaultOptions, ...options });
                
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
                
                return await response.json();
            } catch (error) {
                lastError = error;
                console.warn(`API request failed (attempt ${i + 1}/${CONFIG.maxRetries}):`, error);
                
                if (i < CONFIG.maxRetries - 1) {
                    // Wait before retry (exponential backoff)
                    await new Promise(resolve => setTimeout(resolve, Math.pow(2, i) * 1000));
                }
            }
        }
        
        throw lastError;
    },

    /**
     * Get system status
     * @returns {Promise} System status data
     */
    async getStatus() {
        return this.request('/status');
    },

    /**
     * Get documents list
     * @param {number} limit - Number of documents to fetch
     * @param {number} offset - Offset for pagination
     * @returns {Promise} Documents data
     */
    async getDocuments(limit = 20, offset = 0) {
        return this.request(`/api/v1/documents?limit=${limit}&offset=${offset}`);
    },

    /**
     * Get specific document
     * @param {string} documentId - Document ID
     * @returns {Promise} Document data
     */
    async getDocument(documentId) {
        return this.request(`/api/v1/documents/${documentId}`);
    }
};

// Status monitoring
const StatusMonitor = {
    intervalId: null,

    /**
     * Start monitoring system status
     */
    start() {
        this.updateStatus();
        this.intervalId = setInterval(() => {
            this.updateStatus();
        }, CONFIG.refreshInterval);
    },

    /**
     * Stop monitoring
     */
    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
    },

    /**
     * Update system status display
     */
    async updateStatus() {
        try {
            const status = await API.getStatus();
            this.displayStatus(status);
        } catch (error) {
            console.error('Failed to update status:', error);
            this.displayError();
        }
    },

    /**
     * Display status information
     * @param {Object} status - Status data
     */
    displayStatus(status) {
        // Update individual status indicators
        const indicators = {
            'db-status': status.database === 'healthy' ? '✓' : '✗',
            'n8n-status': status.services?.n8n === 'healthy' ? '✓' : '✗',
            'qdrant-status': status.services?.qdrant === 'healthy' ? '✓' : '✗',
            'monitoring-status': status.services?.grafana === 'healthy' ? '✓' : '✗'
        };

        Object.entries(indicators).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = value;
                element.className = value === '✓' ? 'text-success' : 'text-danger';
            }
        });

        // Update metrics if available
        if (status.metrics && document.getElementById('system-metrics')) {
            this.displayMetrics(status.metrics);
        }
    },

    /**
     * Display metrics information
     * @param {Object} metrics - Metrics data
     */
    displayMetrics(metrics) {
        const container = document.getElementById('system-metrics');
        if (!container) return;

        container.innerHTML = `
            <div class="row text-center">
                <div class="col-4">
                    <h4>${metrics.uptime_seconds || 0}</h4>
                    <small class="text-muted">Uptime (sec)</small>
                </div>
                <div class="col-4">
                    <h4>${metrics.total_requests || 0}</h4>
                    <small class="text-muted">Total Requests</small>
                </div>
                <div class="col-4">
                    <h4>${((metrics.error_rate || 0) * 100).toFixed(2)}%</h4>
                    <small class="text-muted">Error Rate</small>
                </div>
            </div>
        `;
    },

    /**
     * Display error state
     */
    displayError() {
        const indicators = ['db-status', 'n8n-status', 'qdrant-status', 'monitoring-status'];
        
        indicators.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = '?';
                element.className = 'text-warning';
            }
        });
    }
};

// Document management
const DocumentManager = {
    currentPage: 0,
    pageSize: 20,

    /**
     * Load documents list
     * @param {number} page - Page number
     */
    async loadDocuments(page = 0) {
        const container = document.getElementById('documents-table');
        if (!container) return;

        try {
            Utils.showLoading(container);
            
            const documents = await API.getDocuments(this.pageSize, page * this.pageSize);
            this.displayDocuments(documents, page);
            this.currentPage = page;
            
        } catch (error) {
            console.error('Failed to load documents:', error);
            Utils.showError(container, 'Failed to load documents. Please try again.');
        }
    },

    /**
     * Display documents in table
     * @param {Array} documents - Documents array
     * @param {number} page - Current page
     */
    displayDocuments(documents, page) {
        const container = document.getElementById('documents-table');
        
        if (documents.length === 0 && page === 0) {
            container.innerHTML = `
                <div class="text-center text-muted">
                    <i class="fas fa-file-alt fa-3x mb-3"></i>
                    <h5>No documents found</h5>
                    <p>Upload documents through N8N workflows to see them here.</p>
                </div>
            `;
            return;
        }

        let html = `
            <div class="table-responsive">
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>Filename</th>
                            <th>Status</th>
                            <th>Created</th>
                            <th>Processed</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
        `;

        documents.forEach(doc => {
            const statusClass = this.getStatusClass(doc.status);
            html += `
                <tr>
                    <td>
                        <i class="fas fa-file-alt me-2"></i>
                        ${doc.filename}
                    </td>
                    <td>
                        <span class="badge bg-${statusClass}">${doc.status}</span>
                    </td>
                    <td>${Utils.formatDate(doc.created_at)}</td>
                    <td>${Utils.formatDate(doc.processed_at)}</td>
                    <td>
                        <button class="btn btn-sm btn-outline-info" onclick="DocumentManager.viewDocument('${doc.id}')">
                            <i class="fas fa-eye"></i> View
                        </button>
                    </td>
                </tr>
            `;
        });

        html += '</tbody></table></div>';

        // Add pagination
        if (documents.length === this.pageSize || page > 0) {
            html += this.renderPagination(page, documents.length === this.pageSize);
        }

        container.innerHTML = html;
    },

    /**
     * Get Bootstrap class for document status
     * @param {string} status - Document status
     * @returns {string} Bootstrap class name
     */
    getStatusClass(status) {
        const statusClasses = {
            'processed': 'success',
            'processing': 'warning',
            'error': 'danger',
            'pending': 'secondary'
        };
        return statusClasses[status] || 'secondary';
    },

    /**
     * Render pagination controls
     * @param {number} currentPage - Current page number
     * @param {boolean} hasNext - Whether there are more pages
     * @returns {string} Pagination HTML
     */
    renderPagination(currentPage, hasNext) {
        let html = '<nav><ul class="pagination justify-content-center">';
        
        if (currentPage > 0) {
            html += `
                <li class="page-item">
                    <button class="page-link" onclick="DocumentManager.loadDocuments(${currentPage - 1})">Previous</button>
                </li>
            `;
        }
        
        html += `<li class="page-item active"><span class="page-link">${currentPage + 1}</span></li>`;
        
        if (hasNext) {
            html += `
                <li class="page-item">
                    <button class="page-link" onclick="DocumentManager.loadDocuments(${currentPage + 1})">Next</button>
                </li>
            `;
        }
        
        html += '</ul></nav>';
        return html;
    },

    /**
     * View document details
     * @param {string} documentId - Document ID
     */
    async viewDocument(documentId) {
        try {
            const document = await API.getDocument(documentId);
            this.showDocumentModal(document);
        } catch (error) {
            console.error('Failed to load document:', error);
            Utils.showToast('Failed to load document details', 'error');
        }
    },

    /**
     * Show document details in modal
     * @param {Object} document - Document data
     */
    showDocumentModal(document) {
        const statusClass = this.getStatusClass(document.status);
        const modalContent = `
            <div class="row">
                <div class="col-md-6">
                    <h6>Basic Information</h6>
                    <table class="table table-sm">
                        <tr><th>ID:</th><td><code>${document.id}</code></td></tr>
                        <tr><th>Filename:</th><td>${document.filename}</td></tr>
                        <tr><th>Status:</th><td><span class="badge bg-${statusClass}">${document.status}</span></td></tr>
                    </table>
                </div>
                <div class="col-md-6">
                    <h6>Timestamps</h6>
                    <table class="table table-sm">
                        <tr><th>Created:</th><td>${Utils.formatDateTime(document.created_at)}</td></tr>
                        <tr><th>Processed:</th><td>${Utils.formatDateTime(document.processed_at)}</td></tr>
                    </table>
                </div>
            </div>
        `;

        const modalElement = document.getElementById('documentModal');
        const modalContentElement = document.getElementById('modal-content');
        
        if (modalElement && modalContentElement) {
            modalContentElement.innerHTML = modalContent;
            const modal = new bootstrap.Modal(modalElement);
            modal.show();
        }
    }
};

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    console.log('N8N AI Starter Kit Web Interface loaded');
    
    // Start status monitoring if on dashboard
    if (document.getElementById('db-status')) {
        StatusMonitor.start();
    }
    
    // Load documents if on documents page
    if (document.getElementById('documents-table')) {
        DocumentManager.loadDocuments();
    }
    
    // Global error handler
    window.addEventListener('error', function(event) {
        console.error('JavaScript error:', event.error);
    });
    
    // Handle page visibility changes
    document.addEventListener('visibilitychange', function() {
        if (document.visibilityState === 'visible') {
            // Refresh data when page becomes visible
            if (StatusMonitor.intervalId) {
                StatusMonitor.updateStatus();
            }
        }
    });
});

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    StatusMonitor.stop();
});

// Export for global use
window.N8NKit = {
    Utils,
    API,
    StatusMonitor,
    DocumentManager
};