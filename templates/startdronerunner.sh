#!/bin/bash
  
docker run -d \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DRONE_RPC_PROTO="{{ dronerunner_drone_rpc_proto }}" \
  -e DRONE_RPC_HOST="{{ dronerunner_drone_rpc_host }}" \
  -e DRONE_RPC_SECRET="{{ dronerunner_drone_rpc_secret }}" \
  -e DRONE_RUNNER_CAPACITY="{{ dronerunner_drone_runner_capacity }}" \
  -e DRONE_RUNNER_NAME="{{ dronerunner_drone_runner_name }}" \
  -e DRONE_DEBUG="{{ dronerunner_drone_logs_debug }}" \
  -e DRONE_TRACE="{{ dronerunner_drone_logs_trace }}" \
  -e DRONE_AGENT_ARCH="{{ dronerunner_drone_agent_arch }}" \
  -e DRONE_RUNNER_LABELS="{{ dronerunner_labels }}" \
  -p 3000:3000 \
  --restart always \
  --name runner \
  {{ dronerunner_docker_image }}
