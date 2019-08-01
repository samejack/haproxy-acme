
# Create or scale-out server
```
curl -XPUT -L http://127.0.0.1:2379/v2/keys/services/web/domain.com/server-1 -d value="192.168.0.1:80"
```

# Remove server
```
curl -XDELETE -L http://127.0.0.1:2379/v2/keys/services/web/domain.com/1
```

# Show server config
```
curl -XGET -L http://127.0.0.1:2379/v2/keys/services/web/domain.com
```

# Enabled HAProxy stats
Append environment as follows, and use web browser open https://127.0.0.1/stats to login with username and password.
```
    environment:
      - STATS_SERVICE=enable
      - STATS_ENTRYPOINT=/stats
      - STATS_USERNAME=admin
      - STATS_PASSWORD=admin
```
Must to be restart container.