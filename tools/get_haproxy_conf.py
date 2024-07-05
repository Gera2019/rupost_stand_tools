import sys

def generate_config(node_count, num_grp):
    sections = [
        {'name': 'backend cluster-healthcheck', 
         'pre_nodes': '''  option httpchk\n  option log-health-checks\n  http-check expect status 200\n  default-server check port 32000 inter 1s downinter 1s fall 2 rise 1''',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}'},
        {'name': 'backend admin-healthcheck', 
         'pre_nodes': '''  option tcp-check\n  tcp-check connect port 5000\n  default-server check inter 5s downinter 1s fall 2 rise 1''',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}'},
        {'name': 'listen smtp_mx', 
         'pre_nodes': '  bind :25\n  mode tcp\n  balance roundrobin\n  default-server send-proxy on-marked-down shutdown-sessions',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:25 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen smtp_mua', 
         'pre_nodes': '  bind :465\n  mode tcp\n  balance roundrobin\n  default-server send-proxy',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:465 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen imap_mua',
         'pre_nodes': '  bind :993\n  mode tcp\n  balance roundrobin\n  default-server send-proxy on-marked-down shutdown-sessions',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:993 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen sieve', 
         'pre_nodes': '  bind :4190\n  mode tcp\n  balance roundrobin\n  default-server send-proxy',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:4190 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen autoconfig', 
         'pre_nodes': '  bind :80\n  mode tcp\n  balance roundrobin\n  default-server send-proxy on-marked-down shutdown-sessions',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:80 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen web_mua', 
         'pre_nodes': '  bind :443\n  mode tcp\n  balance roundrobin\n  option abortonclose\n  default-server send-proxy on-marked-down shutdown-sessions',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:443 track cluster-healthcheck/node{node_num}'},
        {'name': 'listen web_adm', 
         'pre_nodes': '  bind :5000\n  mode tcp\n  balance roundrobin',
         'node_string': '\n  server node{node_num} grp{num_grp}-rupost{node_num}:5000 track admin-healthcheck/node{node_num}'},
    ]
  
    configString = '''
global
  stats socket /run/haproxy-admin.sock user haproxy group haproxy mode 600 level admin expose-fd listeners
  log /dev/null local0 debug
  user haproxy
  group haproxy
  daemon

defaults
  log global
  option tcplog
  timeout connect 10s
  timeout server 30m
  timeout client 30m'''

    for section in sections:
        configString += '\n\n' + section['name']
        configString += '\n'+section['pre_nodes']
        for i in range(1, node_count + 1):
            configString += section['node_string'].format(node_num=str(i),num_grp=num_grp)

    configString += '''

frontend stats
    bind *:8888
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth rupost:rupost'''

    return configString

# использование функции с аргументом из командной строки
node_count = int(sys.argv[1])
num_grp = int(sys.argv[2])
print(generate_config(node_count, num_grp))
