#!/usr/bin/env bash
# ==============================================================================
# BÀI TẬP 4: THIẾT LẬP CUSTOM NETWORK & NAMED VOLUME BẰNG DOCKER CLI
# Repository path: homework/session_10/ex4/
# File: commands.sh
# ==============================================================================

set -e

echo "======================================================================"
echo ">> [BẮT ĐẦU] BÀI TẬP 4: CUSTOM NETWORK & NAMED VOLUME (DOCKER CLI)"
echo "======================================================================"

# Dọn dẹp tài nguyên cũ nếu có (đảm bảo tính idempotent khi chạy lại)
echo ">> [0/6] Dọn dẹp môi trường cũ (nếu có)..."
docker rm -f app-container db-server 2>/dev/null || true
docker network rm app-net 2>/dev/null || true
docker volume rm db-data 2>/dev/null || true

# ------------------------------------------------------------------------------
# BƯỚC 1: Tạo Custom Bridge Network tên app-net
# ------------------------------------------------------------------------------
echo ""
echo ">> [1/6] Tạo Custom Bridge Network: app-net..."
docker network create --driver bridge app-net

# ------------------------------------------------------------------------------
# BƯỚC 2: Tạo Named Volume tên db-data
# ------------------------------------------------------------------------------
echo ""
echo ">> [2/6] Tạo Named Volume: db-data..."
docker volume create db-data

# ------------------------------------------------------------------------------
# BƯỚC 3: Khởi chạy Database Container (postgres:15-alpine) tên db-server
#         - Tham gia custom network: app-net
#         - Mount named volume: db-data -> /var/lib/postgresql/data
# ------------------------------------------------------------------------------
echo ""
echo ">> [3/6] Khởi chạy Database Container (postgres:15-alpine) tên db-server..."
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine

echo ">> Đang đợi PostgreSQL khởi động hoàn tất..."
until docker exec db-server pg_isready -U postgres -d testdb >/dev/null 2>&1; do
  sleep 1
done
echo ">> PostgreSQL db-server đã sẵn sàng nhận kết nối!"

# ------------------------------------------------------------------------------
# BƯỚC 4: Khởi chạy Backend Container tên app-container
#         - Tham gia custom network: app-net
#         - Truyền biến môi trường kết nối DB qua hostname db-server
# ------------------------------------------------------------------------------
echo ""
echo ">> [4/6] Khởi chạy Backend Container (app-container)..."

# Build backend image nếu có Dockerfile tại thư mục hiện tại
if [ -f Dockerfile ]; then
  echo ">> Tìm thấy Dockerfile, đang build image app-backend:v1..."
  docker build -t app-backend:v1 .
  BACKEND_IMAGE="app-backend:v1"
else
  # Fallback: sử dụng node:18-alpine nếu chạy script độc lập
  echo ">> Sử dụng base image node:18-alpine làm backend..."
  BACKEND_IMAGE="node:18-alpine"
fi

if [ "$BACKEND_IMAGE" = "app-backend:v1" ]; then
  docker run -d \
    --name app-container \
    --network app-net \
    -p 3000:3000 \
    -e DB_HOST=db-server \
    -e DB_PORT=5432 \
    -e DB_USER=postgres \
    -e DB_PASSWORD=postgres \
    -e DB_NAME=testdb \
    app-backend:v1
else
  docker run -d \
    --name app-container \
    --network app-net \
    -p 3000:3000 \
    -e DB_HOST=db-server \
    -e DB_PORT=5432 \
    -e DB_USER=postgres \
    -e DB_PASSWORD=postgres \
    -e DB_NAME=testdb \
    node:18-alpine sh -c "node -e 'const http=require(\"http\"); const server=http.createServer((req,res)=>{res.writeHead(200,{\"Content-Type\":\"application/json\"});res.end(JSON.stringify({status:\"healthy\",db_host:process.env.DB_HOST}));});server.listen(3000,()=>console.log(\"Server running on port 3000\"));'"
fi

sleep 2
echo ">> Backend Container app-container đã khởi chạy thành công!"

# ------------------------------------------------------------------------------
# BƯỚC 5: Thực hiện test Data Persistence:
#         1. Thêm dữ liệu vào Database
#         2. Xóa cứng container DB: docker rm -f db-server
#         3. Khởi chạy lại container DB mới gắn cùng Volume db-data
#         4. Xác minh dữ liệu không bị mất
# ------------------------------------------------------------------------------
echo ""
echo ">> [5/6] THỰC HIỆN TEST DATA PERSISTENCE..."

echo "--- 5.1. Thêm dữ liệu mẫu vào PostgreSQL (bảng users) ---"
docker exec -i db-server psql -U postgres -d testdb << 'EOF'
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO users (name, email) VALUES
  ('Nguyen Van A', 'vana@rikkei.edu.vn'),
  ('Tran Thi B', 'thib@rikkei.edu.vn');
EOF

echo "--- Dữ liệu hiện tại trước khi xóa container DB: ---"
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"

echo ""
echo "--- 5.2. Xóa cứng container DB (docker rm -f db-server) ---"
docker rm -f db-server
echo ">> Đã xóa cứng container db-server thành công!"

echo ""
echo "--- 5.3. Kiểm tra Named Volume db-data vẫn tồn tại ---"
docker volume ls | grep db-data

echo ""
echo "--- 5.4. Khởi chạy lại container DB mới gắn cùng Volume db-data ---"
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=testdb \
  postgres:15-alpine

echo ">> Đang đợi PostgreSQL mới sẵn sàng..."
until docker exec db-server pg_isready -U postgres -d testdb >/dev/null 2>&1; do
  sleep 1
done
echo ">> Container db-server mới đã sẵn sàng!"

echo ""
echo "--- 5.5. Xác minh dữ liệu không bị mất (Data Persistence Verified) ---"
docker exec -i db-server psql -U postgres -d testdb -c "SELECT * FROM users;"

# ------------------------------------------------------------------------------
# BƯỚC 6: Thực thi các lệnh kiểm tra theo yêu cầu đề bài
# ------------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo ">> [6/6] CÁC LỆNH KIỂM TRA THEO YÊU CẦU ĐỀ BÀI:"
echo "======================================================================"

echo ""
echo ">> [Lệnh kiểm tra 1]: docker network ls | grep app-net"
docker network ls | grep app-net

echo ""
echo ">> [Lệnh kiểm tra 2]: docker volume ls | grep db-data"
docker volume ls | grep db-data

echo ""
echo ">> [Lệnh kiểm tra 3]: docker network inspect app-net"
docker network inspect app-net

echo ""
echo ">> [Lệnh kiểm tra 4]: docker exec app-container ping -c 2 db-server"
# Lưu ý: Trong terminal tương tác thủ công có thể dùng: docker exec -it app-container ping -c 2 db-server
docker exec app-container ping -c 2 db-server

echo ""
echo "======================================================================"
echo ">> [HOÀN TẤT] TẤT CẢ CÁC BƯỚC ĐÃ THỰC THI THÀNH CÔNG RỰC RỠ!"
echo "======================================================================"
