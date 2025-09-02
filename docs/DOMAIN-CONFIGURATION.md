# Domain Configuration Guide

This guide explains how to configure domains for both development and production environments in the N8N AI Starter Kit.

## 🛠 Configuration Methods

### Interactive Setup (Recommended)

The easiest way to configure your domain is using the interactive setup script:

```bash
./scripts/setup.sh
```

The script will prompt you to enter your domain name:
```
Enter your domain name (or press Enter for localhost):
```

- For **development**: Press Enter to use `localhost`
- For **production**: Enter your real domain name (e.g., `example.com`)

### Manual Configuration

You can also manually edit the `.env` file:

```bash
# Edit the .env file
nano .env

# Find and update these lines:
DOMAIN=yourdomain.com
ACME_EMAIL=admin@yourdomain.com
```

## 🌐 Development vs Production

### Development Environment

For local development, use `localhost`:

```
DOMAIN=localhost
ACME_EMAIL=admin@localhost
```

Services will be accessible at:
- N8N: http://n8n.localhost
- Grafana: http://grafana.localhost
- Web Interface: http://api.localhost/ui/
- Traefik Dashboard: http://traefik.localhost

### Production Environment

For production deployments, use your real domain:

```
DOMAIN=example.com
ACME_EMAIL=admin@example.com
```

Services will be accessible at:
- N8N: https://n8n.example.com
- Grafana: https://grafana.example.com
- Web Interface: https://api.example.com/ui/
- Traefik Dashboard: https://traefik.example.com

## 🌍 DNS Configuration

For production deployments, you need to configure DNS records to point to your server:

### Option 1: Individual Records
```
n8n.example.com    -> YOUR_SERVER_IP
grafana.example.com -> YOUR_SERVER_IP
api.example.com    -> YOUR_SERVER_IP
traefik.example.com -> YOUR_SERVER_IP
```

### Option 2: Wildcard Record (Recommended)
```
*.example.com -> YOUR_SERVER_IP
```

## 🔐 SSL/TLS Certificates

The N8N AI Starter Kit automatically handles SSL/TLS certificates:

### Let's Encrypt (Production)

When using a real domain, Traefik automatically requests certificates from Let's Encrypt.

Requirements:
- Domain must point to your server
- Ports 80 and 443 must be accessible from the internet
- Valid email address in `ACME_EMAIL`

### Self-Signed Certificates (Development)

When using `localhost`, self-signed certificates are used for HTTPS.

## 🔒 Traefik Dashboard Security

The Traefik dashboard is protected with basic authentication:

During setup, you'll be prompted to enter a password for the Traefik dashboard:
```
Enter password for Traefik dashboard (or press Enter to generate):
```

- Press Enter to generate a secure password automatically
- Or enter your own password for the dashboard

The default username is `admin`.

To access the Traefik dashboard:
1. Navigate to `https://traefik.yourdomain.com` (production) or `http://traefik.localhost` (development)
2. Enter the username `admin` and the password you configured

## 🔄 Changing Domains

To change your domain after initial setup:

### Method 1: Interactive Reconfiguration
```bash
./scripts/setup.sh --force
```

### Method 2: Manual Update
```bash
# Edit .env file
nano .env

# Update DOMAIN and ACME_EMAIL
DOMAIN=newdomain.com
ACME_EMAIL=admin@newdomain.com

# Restart services
./start.sh restart
```

## 🧪 Testing Domain Configuration

After configuring your domain:

1. **Verify DNS**:
   ```bash
   nslookup n8n.yourdomain.com
   ```

2. **Check service accessibility**:
   ```bash
   curl -I https://n8n.yourdomain.com
   ```

3. **Verify SSL certificate**:
   ```bash
   openssl s_client -connect n8n.yourdomain.com:443
   ```

4. **Test Traefik dashboard access**:
   ```bash
   curl -I https://traefik.yourdomain.com
   ```

## ⚠️ Common Issues

### Certificate Errors

If you encounter certificate errors:
1. Ensure DNS records are properly configured
2. Verify ports 80 and 443 are accessible
3. Check that `ACME_EMAIL` is valid

### Mixed Content Warnings

If you see mixed content warnings:
1. Ensure all services use HTTPS
2. Check N8N configuration for proper protocol settings

### Domain Not Found

If services are not accessible:
1. Verify DNS records point to the correct IP
2. Check firewall settings
3. Ensure Traefik is running properly

### Traefik Dashboard Access Denied

If you can't access the Traefik dashboard:
1. Verify the username is `admin`
2. Check that you're using the correct password
3. Ensure the `TRAEFIK_DASHBOARD_HASHED_PASSWORD` is properly set in `.env`

## 🛡 Security Considerations

1. **Use HTTPS in production**: Never run production services over HTTP
2. **Valid email address**: Use a real email for `ACME_EMAIL` to receive certificate expiration notices
3. **Strong dashboard password**: Use a strong, unique password for the Traefik dashboard
4. **Firewall configuration**: Only expose necessary ports (80, 443)
5. **Regular updates**: Keep certificates and software up to date

## 📚 Additional Resources

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [DNS Configuration Guide](https://www.cloudflare.com/learning/dns/what-is-dns/)