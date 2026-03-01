#!/bin/bash

echo "Starting Nebius VM..."
/Users/eyan/.nebius/bin/nebius compute instance start \
  --id computeinstance-e00hjed0spe2d0abhe

echo "Waiting for VM to boot (30 seconds)..."
sleep 30

echo "Starting vLLM server..."
ssh -i ~/.ssh/nebius_cosmos yeungeyan@89.169.110.39 \
  "cd /mnt/filesystem-g6/elderly-safety-detection && \
   source ~/cosmos-reason2/.venv/bin/activate && \
   nohup vllm serve nvidia/Cosmos-Reason2-2B \
     --trust-remote-code \
     --max-model-len 8192 \
     --dtype bfloat16 \
     --gpu-memory-utilization 0.9 \
     --no-enforce-eager \
     > vllm.log 2>&1 &"

echo "Waiting for vLLM to start (60 seconds)..."
sleep 60

echo "Testing vLLM server..."
curl -s http://89.169.110.39:8000/v1/models | jq '.data[0].id'

echo "✅ Server ready at http://89.169.110.39:8000"
