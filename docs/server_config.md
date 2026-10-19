# Server Configuration

Kamal handles most of it automatically when you run `kamal setup`, but you should do a few things first:

## 1. SSH in and update the system

```bash
ssh your-server
apt update && apt upgrade -y
```

## 2. Set up a basic firewall

```bash
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable
```

## 3. (Optional) Create a swap file

CX22 has 4GB RAM which should be fine, but swap helps if you hit memory pressure during deploys:

```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
exit
```

# 4. Run the setup (on local machine)

Kamal requires server and database credentials plus the IP address to be configured in `config/deploy.yml`.

Kamal will install Docker and everything else.

```bash
kamal setup
```

# 5. Deploy

```bash
kamal deploy
```
