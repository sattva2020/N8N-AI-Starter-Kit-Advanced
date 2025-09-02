# Changelog

All notable changes to the N8N AI Starter Kit project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.5] - 2025-08-31

### Changed

#### API Key Security Enhancement
- **Manual API Key Configuration**: Changed API key handling to require manual user input for security
  - OpenAI API Key for LightRAG service (must be manually added)
  - Qdrant API Key for vector database authentication (must be manually added)
  - N8N API Key as alternative to Personal Access Token (must be manually added)
- **Enhanced Security**: API key fields in template.env are now empty by default
- **User Guidance**: Updated setup script and documentation to inform users they must manually add API keys
- **Documentation Updates**: README.md and other documentation updated to reflect new API key handling

## [1.2.4] - 2025-08-31

### Added

#### Enhanced API Key Configuration
- **Automatic API Key Generation**: Added automatic generation of secure placeholder API keys during setup
  - OpenAI API Key for LightRAG service (64-character hex key)
  - Qdrant API Key for vector database authentication (64-character hex key)
  - N8N API Key as alternative to Personal Access Token (64-character hex key)
- **Placeholder Keys**: All API keys are generated as secure placeholders that can be updated later
- **Enhanced Documentation**: Updated README with API key configuration instructions

### Enhanced

#### Environment Setup
- Improved setup script with automatic API key generation
- Enhanced validation for environment variables
- Better error handling for missing dependencies

## [1.2.3] - 2025-08-31

### Added

#### Enhanced Security Configuration
- **Traefik Dashboard Authentication**: Added basic authentication for Traefik dashboard with interactive password setup
- **Let's Encrypt Email Configuration**: Interactive setup now prompts for Let's Encrypt email address
- **Secure Password Generation**: Automatic generation of secure passwords for all services including Traefik dashboard
- **Enhanced Documentation**: Updated `docs/DOMAIN-CONFIGURATION.md` with security best practices and dashboard access instructions

### Enhanced

#### Environment Setup
- Improved interactive setup script with additional security prompts
- Added Traefik dashboard password configuration with automatic hashing
- Enhanced validation for environment variables
- Better error handling for missing dependencies

#### Docker Compose Configuration
- Added basic authentication for Traefik dashboard
- Improved security headers configuration
- Updated middleware configuration for enhanced security

## [1.2.2] - 2025-08-31

### Added

#### Enhanced Domain Configuration
- **Interactive Domain Setup**: Improved setup script now prompts for domain configuration in interactive mode
- **Production Deployment Guidance**: Added comprehensive domain configuration guide in `docs/DOMAIN-CONFIGURATION.md`
- **Smart Domain Detection**: Startup script now detects localhost usage in production environments and offers to update domain configuration
- **DNS and SSL Documentation**: Detailed instructions for DNS configuration and SSL certificate management

### Enhanced

#### Environment Setup
- Improved domain configuration workflow with better user prompts
- Enhanced validation for production deployments
- Better handling of ACME email configuration based on domain
- Updated README with domain configuration instructions

## [1.2.1] - 2025-08-30

### Added

#### Supabase Integration (Hybrid Database Architecture)
- **Hybrid Database Support**: Added Supabase integration for AI/analytics data storage
  - Local PostgreSQL continues to handle core N8N application data
  - Supabase manages AI/analytics data (document processing results, embeddings, knowledge graphs)
  - Optimal separation of concerns and independent scalability

- **Supabase Profile**: New Docker Compose profile for Supabase integration
  - Enable with `COMPOSE_PROFILES=default,developer,monitoring,supabase`
  - Optional cloud-based data storage for AI workloads
  - Configurable through environment variables

- **Configuration Files**:
  - Updated `env.schema` with Supabase configuration variables
  - Updated `template.env` with Supabase examples and documentation
  - Updated `docker-compose.yml` with Supabase integration documentation

- **Documentation**:
  - New `docs/SUPABASE-INTEGRATION.md` guide with setup instructions
  - Updated `README.md` with hybrid database architecture information
  - Architecture diagram updates to show Supabase integration

### Enhanced

#### Environment Configuration
- Added Supabase configuration variables to environment schema
- Enhanced documentation for hybrid database approach
- Improved profile management with Supabase option

## [1.2.0] - 2025-08-30

### Added

#### Comprehensive Testing Infrastructure
- **Playwright E2E Testing**: Complete end-to-end testing framework
  - Cross-browser testing (Chrome, Firefox)
  - API integration testing
  - Workflow integration testing
  - Performance and security testing
  - Automated test reporting

- **Comprehensive Test Runner** (`scripts/run-comprehensive-tests.sh`): Unified testing orchestration
  - Support for all test types (unit, integration, e2e, api, performance, security)
  - Automated environment setup and cleanup
  - Configurable test timeouts and reporting
  - Integration with existing test infrastructure

#### Enhanced LightRAG Integration
- **Updated Dependencies**: Fixed compatibility issues with latest LightRAG versions
  - Updated to LightRAG >=0.1.0b6 for stability
  - Resolved dependency conflicts
  - Flexible versioning for better compatibility

#### Improved Windows Support
- **Tool Availability**: Enhanced Windows environment compatibility
  - Automatic jq installation for JSON processing
  - PATH configuration improvements
  - Git Bash compatibility enhancements

### Enhanced

#### Script Reliability and Error Handling
- **Monitor Script** (`scripts/maintenance/monitor.sh`): Fixed critical syntax issues
  - Corrected variable scope issues
  - Improved error handling
  - Enhanced command-line interface

- **Start Script** (`start.sh`): Improved project path resolution
  - Fixed PROJECT_ROOT calculation
  - Better environment file handling
  - Enhanced cross-platform compatibility

#### Testing Documentation
- **Testing Protocol** (`docs/TESTING-PROTOCOL.md`): Complete testing guidelines
- **Testing Quickstart** (`docs/TESTING-QUICKSTART.md`): Quick testing setup guide
- **Test Reports**: Automated test result reporting and analysis

### Fixed

#### Dependency Management
- **LightRAG Service**: Resolved package version conflicts
  - Fixed lightrag package version (0.0.0.8 → >=0.1.0b6)
  - Updated Python dependency requirements
  - Improved build reliability

#### Configuration Issues
- **Environment Variables**: Added missing service configuration variables
  - Complete service worker configuration
  - Model configuration defaults
  - API key placeholder handling

#### Cross-Platform Compatibility
- **Windows Compatibility**: Improved Windows environment support
  - Tool installation automation
  - PATH management improvements
  - Script execution reliability

### Performance Improvements
- Enhanced test execution speed through parallel operations
- Improved Docker build performance with dependency caching
- Optimized environment setup and validation

### Developer Experience
- **Enhanced CLI Interfaces**: Better help documentation and error messages
- **Automated Tool Setup**: Automatic installation of required tools
- **Comprehensive Testing**: Full testing coverage across all components
- **Improved Documentation**: Enhanced setup and troubleshooting guides

### Breaking Changes
- None - All changes are backward compatible

### Migration Notes
- LightRAG service will rebuild automatically with new dependencies
- Existing test scripts continue to work alongside new testing infrastructure
- Enhanced testing features are opt-in and don't affect existing workflows

## [1.1.0] - 2024-08-30

### Added

#### Enhanced N8N API Integration
- **Advanced Pagination Support**: Implemented cursor-based pagination for all list operations
  - Configurable page sizes (1-250 items)
  - Automatic next page navigation
  - Support for retrieving all results across multiple pages
  - Compatible with N8N API v1 pagination standards

- **Credential Schema API**: Added dynamic credential schema retrieval
  - Get exact schema requirements for any credential type
  - Support for custom and built-in credential types
  - Real-time schema validation and documentation
  - Available credential types listing

#### New Management Scripts
- **Execution Monitor** (`scripts/n8n-execution-monitor.sh`): Comprehensive workflow execution monitoring
  - Real-time execution tracking with auto-refresh
  - Advanced filtering by workflow, status, date range
  - Performance metrics and analytics
  - Export capabilities to JSON format
  - Execution duration calculations and statistics
  - Error analysis and debugging tools

- **Workflow Manager** (`scripts/n8n-workflow-manager.sh`): Complete workflow lifecycle management
  - Workflow activation/deactivation automation
  - Health monitoring and issue detection
  - Performance metrics and optimization recommendations
  - Import/export functionality with version control
  - Bulk operations for workflow management
  - Workflow duplication and templating

#### Security Enhancements
- **Integrated Security Auditing**: Enhanced monitoring with built-in security assessment
  - N8N API security audit integration
  - Credential security validation
  - Workflow security risk analysis
  - Docker container security assessment
  - Infrastructure security monitoring
  - Automated security score calculation

- **Multi-layer Security Monitoring**: Comprehensive security coverage
  - API authentication validation
  - Network security assessment
  - Permission and access control auditing
  - Vulnerability scanning integration
  - Security metric collection for Prometheus

### Enhanced

#### Credential Management (`create_n8n_credential.sh`)
- Added pagination support for large credential sets
- Implemented credential schema retrieval via API
- Enhanced error handling with detailed HTTP status reporting
- Added credential type listing and documentation
- Improved bulk operations with progress tracking
- Enhanced validation with API-driven schema checking

#### Monitoring System (`scripts/maintenance/monitor.sh`)
- Integrated N8N API security audit functionality
- Added credential and workflow security validation
- Enhanced Docker security assessment
- Improved error detection and reporting
- Added security scoring and risk assessment
- Enhanced integration with existing monitoring stack

### API Features

#### Full N8N API Coverage
- **Authentication**: Support for both PAT and API Key methods
- **Workflows**: Create, read, update, delete, activate, deactivate
- **Executions**: List, filter, analyze, export execution data
- **Credentials**: Enhanced CRUD operations with schema validation
- **Audit**: Built-in security audit with configurable categories

#### Advanced Filtering and Search
- Multi-criteria filtering for workflows and executions
- Date range filtering with ISO 8601 support
- Status-based filtering (success, error, waiting, running)
- Workflow name and tag-based search
- Performance-based filtering and sorting

#### Export and Integration
- JSON export for all data types
- Prometheus metrics integration
- Grafana dashboard compatibility
- Webhook notification support
- External system integration APIs

### Documentation
- **API Enhancement Guide**: Comprehensive documentation for new API features
- **Security Audit Documentation**: Security monitoring and audit procedures
- **Advanced Usage Examples**: Real-world scenarios and best practices
- **Troubleshooting Guide**: Enhanced with API-specific troubleshooting
- **Integration Patterns**: Documentation for external system integration

### Performance Improvements
- Optimized API request batching for large datasets
- Enhanced error recovery and retry mechanisms
- Improved pagination performance for large result sets
- Background processing for long-running operations
- Caching mechanisms for frequently accessed data

### Developer Experience
- Enhanced CLI interfaces with better help documentation
- Improved error messages with actionable recommendations
- Better progress reporting for long-running operations
- Development mode with dry-run capabilities
- Enhanced debugging and verbose output options

### Breaking Changes
- None - All changes are backward compatible

### Migration Notes
- Existing scripts continue to work without modification
- New features are opt-in and don't affect existing workflows
- Enhanced pagination is automatically available for all list operations
- Security audit features require N8N API authentication

## [1.0.0] - 2024-01-01

### Added

#### Core Infrastructure
- Complete Docker Compose deployment with Traefik reverse proxy
- Automatic TLS certificate generation via Let's Encrypt
- Production-ready security with HTTPS redirects and security headers
- Cross-platform support (Linux, macOS, Windows with Git Bash)

#### N8N Integration
- N8N workflow automation engine with PostgreSQL backend
- Comprehensive credential management system with REST API support
- Support for both Personal Access Token and Public API Key authentication
- Automatic credential type normalization and placeholder expansion

#### AI Services
- **Document Processor**: FastAPI service with SentenceTransformers integration
  - Multi-format document processing (PDF, DOCX, TXT, MD)
  - Intelligent text chunking with configurable overlap
  - Vector embedding generation and storage
  - Background processing with progress tracking
  
- **ETL Processor**: Scheduled data pipeline service
  - Workflow execution data synchronization
  - Document processing metrics aggregation
  - APScheduler integration with cron and interval triggers
  - Analytics data preparation for ClickHouse

- **Web Interface**: Management dashboard and API gateway
  - Responsive Bootstrap 5 interface
  - Real-time service monitoring
  - Document management interface
  - System health dashboards

#### Data Storage
- **PostgreSQL**: Primary database with pgvector extension for vector operations
- **Qdrant**: High-performance vector similarity search engine
- **ClickHouse**: Optional analytics database for time-series data

#### Monitoring & Observability
- **Grafana**: Pre-configured dashboards for system monitoring
- **Prometheus**: Metrics collection with custom service exporters
- Comprehensive health check endpoints across all services
- Structured logging with JSON format

#### Development & Operations
- **Environment Management**: Template-based configuration with secure password generation
- **Backup & Restore**: Comprehensive backup system with compression and retention
- **Monitoring Tools**: System health monitoring with alerting capabilities
- **Testing Framework**: Unit and integration tests with cross-platform support

#### Scripts & Automation
- **start.sh**: Main deployment script with profile support
- **setup.sh**: Environment initialization with security best practices
- **create_n8n_credential.sh**: Advanced credential management with bulk operations
- **Maintenance Scripts**: Backup, restore, and monitoring utilities

### Security Features
- Zero-secret repository design with template-based environment generation
- Strong password generation using OpenSSL
- Network isolation with Docker bridge networking
- Automatic security headers (HSTS, CSP, X-Frame-Options)
- Input validation and sanitization across all services

### Documentation
- Comprehensive README with quick start guide
- Technical design document (project.md) with architecture details
- AI agent instructions for development guidelines
- Complete API documentation with examples
- Troubleshooting guide with common issues and solutions

### Deployment Profiles
- **default**: Core services (Traefik, N8N, PostgreSQL)
- **developer**: + Qdrant, Web Interface, Document Processor
- **monitoring**: + Grafana, Prometheus
- **analytics**: + ETL Processor, ClickHouse

### Cross-Platform Compatibility
- Windows support via Git Bash
- macOS compatibility with Homebrew dependencies
- Linux support (Ubuntu, CentOS, Alpine)
- Docker volume persistence across platforms

### Performance Optimizations
- Connection pooling for database connections
- Background task processing for CPU-intensive operations
- Configurable worker counts for scaling
- Health check optimization with appropriate timeouts
- Resource monitoring and alerting

### Configuration Management
- Environment schema documentation (env.schema)
- Template-based configuration (template.env)
- Profile-based service composition
- Runtime configuration validation
- Hot-reload support for development

[1.0.0]: https://github.com/your-org/n8n-ai-starter-kit/releases/tag/v1.0.0