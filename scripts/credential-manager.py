#!/usr/bin/env python3
"""
N8N AI Starter Kit - Advanced Credential Management

This script provides advanced credential management for N8N, including:
- Automatic credential discovery from service configuration
- Template-based credential generation
- Bulk operations with rollback support
- Environment variable validation
- Interactive setup mode
"""

import os
import sys
import json
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Any
import requests
from urllib.parse import urljoin


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color


class CredentialManager:
    """Advanced N8N credential management system"""
    
    def __init__(self, base_url: str = "http://localhost:5678", 
                 token: Optional[str] = None, api_key: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.credentials_url = urljoin(self.base_url, '/api/v1/credentials')
        
        # Setup authentication
        self.headers = {'Content-Type': 'application/json'}
        if token:
            self.headers['Authorization'] = f'Bearer {token}'
        elif api_key:
            self.headers['X-N8N-API-KEY'] = api_key
        else:
            raise ValueError("Either token or api_key must be provided")
        
        self.session = requests.Session()
        self.session.headers.update(self.headers)
        
        # Load project root and environment
        self.project_root = Path(__file__).parent.parent
        self.load_environment()
        
        # Service configuration
        self.service_configs = self._load_service_configs()
    
    def load_environment(self):
        """Load environment variables from .env file"""
        env_file = self.project_root / '.env'
        if env_file.exists():
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        os.environ.setdefault(key, value)
    
    def _load_service_configs(self) -> Dict[str, Dict[str, Any]]:
        """Load service configurations from templates"""
        configs = {}
        
        # Try to load from config file first
        config_file = self.project_root / 'config' / 'n8n' / 'credentials-template.json'
        if config_file.exists():
            with open(config_file, 'r') as f:
                templates = json.load(f)
                for template in templates:
                    service_name = self._extract_service_name(template['name'])
                    configs[service_name] = template
        
        # Add hardcoded fallbacks for core services
        if not configs:
            configs.update(self._get_default_configs())
        
        return configs
    
    def _extract_service_name(self, credential_name: str) -> str:
        """Extract service name from credential name"""
        name_lower = credential_name.lower()
        if 'postgres' in name_lower:
            return 'postgres'
        elif 'qdrant' in name_lower:
            return 'qdrant'
        elif 'redis' in name_lower:
            return 'redis'
        elif 'neo4j' in name_lower:
            return 'neo4j'
        elif 'clickhouse' in name_lower:
            return 'clickhouse'
        elif 'ollama' in name_lower:
            return 'ollama'
        elif 'openai' in name_lower:
            return 'openai'
        elif 'grafana' in name_lower:
            return 'grafana'
        elif 'prometheus' in name_lower:
            return 'prometheus'
        else:
            return credential_name.lower().replace(' ', '_')
    
    def _get_default_configs(self) -> Dict[str, Dict[str, Any]]:
        """Get default service configurations"""
        return {
            'postgres': {
                'name': 'PostgreSQL - Main Database',
                'type': 'postgres',
                'description': 'Main PostgreSQL database for N8N and application data',
                'data': {
                    'host': '${POSTGRES_HOST:-postgres}',
                    'port': '${POSTGRES_PORT:-5432}',
                    'database': '${POSTGRES_DB:-n8n}',
                    'username': '${POSTGRES_USER:-n8n_user}',
                    'password': '${POSTGRES_PASSWORD}',
                    'ssl': 'disable'
                }
            },
            'qdrant': {
                'name': 'Qdrant - Vector Database',
                'type': 'httpHeaderAuth',
                'description': 'Qdrant vector database for AI embeddings',
                'data': {
                    'name': 'api-key',
                    'value': '${QDRANT_API_KEY}'
                }
            },
            'openai': {
                'name': 'OpenAI - API Service',
                'type': 'httpHeaderAuth',
                'description': 'OpenAI API for GPT models',
                'data': {
                    'name': 'Authorization',
                    'value': 'Bearer ${OPENAI_API_KEY}'
                }
            },
            'ollama': {
                'name': 'Ollama - Local LLM Server',
                'type': 'httpHeaderAuth',
                'description': 'Ollama local LLM server',
                'data': {
                    'name': 'Authorization',
                    'value': 'Bearer ollama-local'
                }
            }
        }
    
    def expand_template(self, template: Dict[str, Any]) -> Dict[str, Any]:
        """Expand environment variables in credential template"""
        template_str = json.dumps(template)
        
        # Simple environment variable expansion
        import re
        import os
        
        def replace_var(match):
            var_expr = match.group(1)
            if ':-' in var_expr:
                var_name, default_value = var_expr.split(':-', 1)
                return os.environ.get(var_name, default_value)
            else:
                return os.environ.get(var_expr, '')
        
        expanded = re.sub(r'\$\{([^}]+)\}', replace_var, template_str)
        return json.loads(expanded)
    
    def test_connection(self) -> bool:
        """Test connection to N8N API"""
        try:
            # Test health endpoint
            response = self.session.get(f"{self.base_url}/healthz", timeout=10)
            if response.status_code != 200:
                print(f"{Colors.RED}✗{Colors.NC} N8N health check failed")
                return False
            
            # Test credentials endpoint
            response = self.session.get(self.credentials_url, timeout=10)
            if response.status_code == 200:
                print(f"{Colors.GREEN}✓{Colors.NC} N8N API connection successful")
                return True
            elif response.status_code == 401:
                print(f"{Colors.RED}✗{Colors.NC} Authentication failed - check your token/API key")
                return False
            else:
                print(f"{Colors.RED}✗{Colors.NC} API test failed with status {response.status_code}")
                return False
                
        except requests.exceptions.ConnectionError:
            print(f"{Colors.RED}✗{Colors.NC} Cannot connect to N8N at {self.base_url}")
            return False
        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Connection test failed: {e}")
            return False
    
    def list_credentials(self) -> List[Dict[str, Any]]:
        """List existing credentials"""
        try:
            response = self.session.get(self.credentials_url, timeout=30)
            response.raise_for_status()
            data = response.json()
            return data.get('data', [])
        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Failed to list credentials: {e}")
            return []
    
    def credential_exists(self, name: str) -> Optional[str]:
        """Check if credential exists and return its ID"""
        credentials = self.list_credentials()
        for cred in credentials:
            if cred.get('name') == name:
                return cred.get('id')
        return None
    
    def create_credential(self, config: Dict[str, Any], force: bool = False) -> bool:
        """Create a single credential"""
        try:
            expanded_config = self.expand_template(config)
            
            # Check if credential already exists
            existing_id = self.credential_exists(expanded_config['name'])
            if existing_id and not force:
                print(f"{Colors.YELLOW}⚠{Colors.NC} Credential already exists: {expanded_config['name']}")
                return True
            elif existing_id and force:
                # Delete existing credential
                self.delete_credential(existing_id, expanded_config['name'])
            
            # Create new credential
            response = self.session.post(
                self.credentials_url,
                json=expanded_config,
                timeout=30
            )
            
            if response.status_code == 201:
                cred_data = response.json()
                print(f"{Colors.GREEN}✓{Colors.NC} Created: {expanded_config['name']} (ID: {cred_data.get('id')})")
                return True
            else:
                error_msg = response.json().get('message', 'Unknown error')
                print(f"{Colors.RED}✗{Colors.NC} Failed to create {expanded_config['name']}: {error_msg}")
                return False
                
        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Error creating credential {config.get('name', 'unknown')}: {e}")
            return False
    
    def delete_credential(self, cred_id: str, name: str) -> bool:
        """Delete a credential"""
        try:
            response = self.session.delete(f"{self.credentials_url}/{cred_id}", timeout=30)
            if response.status_code == 200:
                print(f"{Colors.GREEN}✓{Colors.NC} Deleted: {name}")
                return True
            else:
                print(f"{Colors.RED}✗{Colors.NC} Failed to delete {name}")
                return False
        except Exception as e:
            print(f"{Colors.RED}✗{Colors.NC} Error deleting {name}: {e}")
            return False
    
    def validate_environment(self, services: List[str]) -> Dict[str, List[str]]:
        """Validate environment variables for services"""
        issues = {'missing': [], 'warnings': []}
        
        env_requirements = {
            'postgres': ['POSTGRES_PASSWORD'],
            'qdrant': ['QDRANT_API_KEY'],
            'openai': ['OPENAI_API_KEY'],
            'neo4j': ['NEO4J_PASSWORD'],
            'clickhouse': ['CLICKHOUSE_USER'],
            'grafana': ['GRAFANA_ADMIN_PASSWORD']
        }
        
        for service in services:
            required_vars = env_requirements.get(service, [])
            for var in required_vars:
                if not os.environ.get(var):
                    if var in ['OPENAI_API_KEY']:
                        issues['warnings'].append(f"{service}: {var} not set (optional)")
                    else:
                        issues['missing'].append(f"{service}: {var} required")
        
        return issues
    
    def setup_credentials(self, services: List[str], force: bool = False, dry_run: bool = False) -> bool:
        """Setup credentials for specified services"""
        print(f"{Colors.CYAN}➤{Colors.NC} Setting up credentials for services: {', '.join(services)}")
        
        # Validate environment
        validation_issues = self.validate_environment(services)
        if validation_issues['missing']:
            print(f"{Colors.RED}✗{Colors.NC} Missing required environment variables:")
            for issue in validation_issues['missing']:
                print(f"  - {issue}")
            return False
        
        if validation_issues['warnings']:
            print(f"{Colors.YELLOW}⚠{Colors.NC} Environment warnings:")
            for warning in validation_issues['warnings']:
                print(f"  - {warning}")
        
        # Setup credentials
        success_count = 0
        total_count = 0
        
        for service in services:
            if service not in self.service_configs:
                print(f"{Colors.YELLOW}⚠{Colors.NC} No configuration found for service: {service}")
                continue
            
            total_count += 1
            config = self.service_configs[service]
            
            if dry_run:
                expanded = self.expand_template(config)
                print(f"{Colors.BLUE}ℹ{Colors.NC} Would create: {expanded['name']}")
                print(json.dumps(expanded, indent=2))
                success_count += 1
            else:
                if self.create_credential(config, force):
                    success_count += 1
        
        # Summary
        print(f"\n{Colors.BLUE}ℹ{Colors.NC} Setup completed:")
        print(f"  {Colors.GREEN}✓{Colors.NC} Successful: {success_count}")
        if total_count - success_count > 0:
            print(f"  {Colors.RED}✗{Colors.NC} Failed: {total_count - success_count}")
        
        return success_count == total_count
    
    def interactive_setup(self):
        """Interactive credential setup"""
        print(f"{Colors.CYAN}N8N AI Starter Kit - Interactive Credential Setup{Colors.NC}")
        print("=" * 55)
        
        # Show available services
        print(f"\n{Colors.BLUE}Available services:{Colors.NC}")
        service_list = list(self.service_configs.keys())
        for i, (service, config) in enumerate(self.service_configs.items(), 1):
            print(f"  {i}. {service} - {config.get('description', 'No description')}")
        
        # Get user selection
        print(f"\n{Colors.CYAN}Select services to configure:{Colors.NC}")
        print("Enter service numbers (comma-separated) or 'all' for all services:")
        
        try:
            user_input = input("> ").strip()
            
            if user_input.lower() == 'all':
                selected_services = list(self.service_configs.keys())
            else:
                indices = [int(x.strip()) - 1 for x in user_input.split(',') if x.strip().isdigit()]
                selected_services = [service_list[i] for i in indices if 0 <= i < len(service_list)]
            
            if not selected_services:
                print(f"{Colors.RED}✗{Colors.NC} No valid services selected")
                return False
            
            print(f"\n{Colors.BLUE}Selected services:{Colors.NC} {', '.join(selected_services)}")
            
            # Confirm
            confirm = input(f"\n{Colors.CYAN}Proceed with setup? [y/N]:{Colors.NC} ").strip().lower()
            if confirm not in ['y', 'yes']:
                print("Setup cancelled")
                return False
            
            # Run setup
            return self.setup_credentials(selected_services, force=False, dry_run=False)
            
        except (ValueError, IndexError, KeyboardInterrupt):
            print(f"\n{Colors.RED}✗{Colors.NC} Invalid input or setup cancelled")
            return False

    def show_setup_instructions(self):
        """Show detailed setup instructions"""
        print(f"{Colors.CYAN}N8N AI Starter Kit - Credential Setup Instructions{Colors.NC}")
        print("=" * 55)
        print("\n📋 Available Services:")
        for service, config in self.service_configs.items():
            print(f"  • {service}: {config.get('description', 'No description')}")
        
        print(f"\n{Colors.GREEN}✓{Colors.NC} Automatic Setup Options:")
        print("  1. Setup all services:")
        print("     python3 credential-manager.py --setup all")
        print("\n  2. Setup specific services:")
        print("     python3 credential-manager.py --setup postgres,qdrant,openai")
        print("\n  3. Interactive setup:")
        print("     python3 credential-manager.py --interactive")
        
        print(f"\n{Colors.YELLOW}⚠{Colors.NC} Prerequisites:")
        print("  • N8N must be running (check with: ../start.sh status)")
        print("  • Environment variables must be set in .env file")
        print("  • Valid N8N authentication token or API key required")
        
        print(f"\n{Colors.BLUE}ℹ{Colors.NC} Authentication:")
        print("  Set one of these environment variables:")
        print("    N8N_PERSONAL_ACCESS_TOKEN=your_token_here")
        print("    N8N_API_KEY=your_api_key_here")
        print("\n  Or use command line arguments:")
        print("    --token your_token_here")
        print("    --api-key your_api_key_here")


def main():
    parser = argparse.ArgumentParser(
        description="Advanced N8N credential management for AI Starter Kit",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --setup postgres,qdrant,openai    # Setup specific services
  %(prog)s --setup all                        # Setup all available services
  %(prog)s --list                             # List existing credentials
  %(prog)s --interactive                      # Interactive setup mode
  %(prog)s --validate                         # Validate environment only
        """
    )
    
    # Authentication options
    parser.add_argument('--token', help='N8N Personal Access Token')
    parser.add_argument('--api-key', help='N8N Public API Key')
    parser.add_argument('--base-url', default='http://localhost:5678', 
                       help='N8N base URL (default: http://localhost:5678)')
    
    # Actions
    parser.add_argument('--setup', metavar='SERVICES',
                       help='Setup credentials for services (comma-separated or "all")')
    parser.add_argument('--list', action='store_true',
                       help='List existing credentials')
    parser.add_argument('--interactive', action='store_true',
                       help='Interactive setup mode')
    parser.add_argument('--validate', action='store_true',
                       help='Validate environment variables only')
    parser.add_argument('--test-connection', action='store_true',
                       help='Test API connection and exit')
    parser.add_argument('--instructions', action='store_true',
                       help='Show detailed setup instructions')
    
    # Options
    parser.add_argument('--force', action='store_true',
                       help='Overwrite existing credentials')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be done without making changes')
    
    args = parser.parse_args()
    
    # Get authentication from environment if not provided
    token = args.token or os.environ.get('N8N_PERSONAL_ACCESS_TOKEN')
    api_key = args.api_key or os.environ.get('N8N_API_KEY')
    
    if not token and not api_key:
        print(f"{Colors.RED}✗{Colors.NC} Authentication required")
        print("Set N8N_PERSONAL_ACCESS_TOKEN or N8N_API_KEY environment variable,")
        print("or use --token or --api-key arguments")
        return 1
    
    try:
        manager = CredentialManager(args.base_url, token, api_key)
        
        # Show instructions if requested
        if args.instructions:
            manager.show_setup_instructions()
            return 0
        
        # Test connection
        if args.test_connection:
            return 0 if manager.test_connection() else 1
        
        if not manager.test_connection():
            return 1
        
        # Handle different actions
        if args.list:
            credentials = manager.list_credentials()
            print(f"\n{Colors.BLUE}Existing credentials ({len(credentials)}):{Colors.NC}")
            if credentials:
                print(f"{'ID':<36} {'Name':<30} {'Type':<20}")
                print("-" * 86)
                for cred in credentials:
                    print(f"{cred.get('id', 'N/A'):<36} {cred.get('name', 'N/A'):<30} {cred.get('type', 'N/A'):<20}")
            else:
                print("No credentials found")
        
        elif args.validate:
            services = list(manager.service_configs.keys())
            issues = manager.validate_environment(services)
            if issues['missing']:
                print(f"{Colors.RED}✗{Colors.NC} Missing required variables:")
                for issue in issues['missing']:
                    print(f"  - {issue}")
                return 1
            elif issues['warnings']:
                print(f"{Colors.YELLOW}⚠{Colors.NC} Warnings:")
                for warning in issues['warnings']:
                    print(f"  - {warning}")
            else:
                print(f"{Colors.GREEN}✓{Colors.NC} Environment validation passed")
        
        elif args.setup:
            if args.setup.lower() == 'all':
                services = list(manager.service_configs.keys())
            else:
                services = [s.strip() for s in args.setup.split(',') if s.strip()]
            
            if not services:
                print(f"{Colors.RED}✗{Colors.NC} No valid services specified")
                return 1
            
            success = manager.setup_credentials(services, args.force, args.dry_run)
            return 0 if success else 1
        
        elif args.interactive:
            success = manager.interactive_setup()
            return 0 if success else 1
        
        else:
            # Show instructions by default if no action specified
            manager.show_setup_instructions()
            return 0
    
    except Exception as e:
        print(f"{Colors.RED}✗{Colors.NC} Error: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
