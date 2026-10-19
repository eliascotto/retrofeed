## Check failed jobs in db

Last 5 jobs with errors:
```sql
SELECT id, job_id, substr(error, 1, 200) FROM solid_queue_failed_executions ORDER BY id DESC LIMIT 5;
```
