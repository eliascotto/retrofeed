# Connect to the database

1. Connect to the server

```bash
ssh your-server
```

2. Find the database container
```bash
docker ps | grep postgres
```

3. Get the container IP

```bash
docker inspect retrofeed-db | grep IPAddress
```

4. Open ssh tunnel to the database

```bash
ssh -L 5432:<CONTAINER_IP>:5432 your-server
```

5. Connect to the database (or use SQL client)

```bash
psql -h localhost -p 5432 -U psqluser -d db_prod
```
