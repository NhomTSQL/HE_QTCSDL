import csv
import random
from datetime import datetime, timedelta

NODE_IDS = [1, 2, 3, 4]
METRIC_TYPE_IDS = [1, 2, 3, 4]

OUTPUT_FILE = 'telemetry_data.csv'
TOTAL_ROWS = 2000000

start_time = datetime.now() - timedelta(days=30)

print("Đang sinh 2 triệu dòng dữ liệu telemetry...")
with open(OUTPUT_FILE, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    for i in range(TOTAL_ROWS):
        node_id = random.choice(NODE_IDS)
        metric_type_id = random.choice(METRIC_TYPE_IDS)
        val = round(random.uniform(10.0, 95.0), 2)
        ts = (start_time + timedelta(seconds=i * 1.2)).strftime('%Y-%m-%d %H:%M:%S')

        writer.writerow([node_id, metric_type_id, val, ts])

        if (i + 1) % 500000 == 0:
            print(f"Đã tạo {i + 1} dòng...")

print(f"Hoàn thành tạo file {OUTPUT_FILE}!")