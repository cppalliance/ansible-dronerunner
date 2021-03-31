
## Ansible role to install drone.io runner

Drone has an autoscaler implementation, which is recommended. However, in some cases it is still useful to be able to install a drone agent on a single physical server where jobs will be run locally.  
  
One approach for dealing with secure tokens is to set up group variables, encrypting the vault file.  
  
vi /etc/ansible/group_vars/dronerunners/vars  
```
---
dronerunner_drone_rpc_proto: "https"
dronerunner_drone_rpc_host: "drone.example.com"
dronerunner_drone_rpc_secret: "{{ vault_dronerunner_drone_rpc_secret }}"
dronerunner_drone_runner_capacity: 6
dronerunner_drone_runner_name: "{{ inventory_hostname }}"
dronerunner_drone_logs_debug: "false"
dronerunner_drone_logs_trace: "false"
```
vi /etc/ansible/group_vars/dronerunners/vault  
```
vault_dronerunner_drone_rpc_secret: the_secret
```
