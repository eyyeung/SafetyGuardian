#!/bin/bash

echo "Stopping vLLM server..."
ssh -i ~/.ssh/nebius_cosmos yeungeyan@89.169.110.39 \
  "pkill -f 'vllm serve'"

sleep 5

echo "Stopping Nebius VM..."
/Users/eyan/.nebius/bin/nebius compute instance stop \
  --id computeinstance-e00hjed0spe2d0abhe

echo "✅ Server stopped"
