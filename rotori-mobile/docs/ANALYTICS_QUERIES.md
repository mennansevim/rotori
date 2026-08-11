# Rota ve Ürün Analitiği Sorguları

Bu sorgular Supabase SQL Editor'de çalıştırılır. Ham satırları dışa aktarmadan
önce mümkün olduğunca toplulaştırılmış sonuç kullan.

## Günlük rota başarı oranı

```sql
select
  date_trunc('day', occurred_at) as day,
  count(*) filter (where phase = 'succeeded') as succeeded,
  count(*) filter (where phase = 'failed') as failed,
  round(
    100.0 * count(*) filter (where phase = 'succeeded') /
    nullif(count(*) filter (where phase in ('succeeded', 'failed')), 0),
    1
  ) as success_pct
from route_generation_logs
where phase in ('succeeded', 'failed')
group by 1
order by 1 desc;
```

## Üretim süresi ve rota büyüklüğü

```sql
select
  date_trunc('day', occurred_at) as day,
  round(avg((metrics->>'elapsedMs')::numeric)) as avg_elapsed_ms,
  round(percentile_cont(0.95) within group (
    order by (metrics->>'elapsedMs')::numeric
  )) as p95_elapsed_ms,
  round(avg((metrics->>'dayCount')::numeric), 1) as avg_days,
  round(avg((metrics->>'activityCount')::numeric), 1) as avg_activities,
  round(avg((metrics->>'totalTravelMinutes')::numeric), 1) as avg_travel_min
from route_generation_logs
where phase = 'succeeded'
group by 1
order by 1 desc;
```

## En çok istenen şehir kombinasyonları

```sql
select request_json->'cityKeys' as city_route, count(*) as requests
from route_generation_logs
where phase = 'started'
group by 1
order by requests desc
limit 25;
```

## Hata aşamaları

```sql
select error_code as stage, count(*) as failures
from route_generation_logs
where phase = 'failed'
group by 1
order by failures desc;
```

## Ekran kullanımı

```sql
select screen, count(*) as views, count(distinct user_id) as users
from analytics_events
where event_name = 'screen_view'
group by 1
order by views desc;
```
