import csv
import random
from datetime import datetime, timedelta

NUM_RECORDS = 2_000_000  
NODES = ['node-001', 'node-002', 'node-003']
METRICS = ['cpu_usage', 'ram_usage', 'temperature', 'disk_io']

OUTPUT_FILE = 'telemetry_data.csv'

print("Đang sinh 2 triệu dòng dữ liệu telemetry...")
start_time = datetime.now() - timedelta(days=30)

with open(OUTPUT_FILE, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    for i in range(NUM_RECORDS):
        node_id = random.choice(NODES)
        metric_name = random.choice(METRICS)
        metric_value = round(random.uniform(10.0, 95.0), 2)
        timestamp = (start_time + timedelta(seconds=i * 1.2)).strftime('%Y-%m-%d %H:%M:%S')
        
        writer.writerow([node_id, metric_name, metric_value, timestamp])
        
        if (i + 1) % 500000 == 0:
            print(f"Đã tạo {i + 1} dòng...")

print(f"Hoàn thành tạo file {OUTPUT_FILE}!")