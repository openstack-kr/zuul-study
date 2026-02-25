# Zuul Pipeline의 실행 흐름과 Build Node lifecycle

## 1. 주제 선정 이유

Zuul은 speculative gating 기능을 갖춘 이벤트 기반 CI/CD 시스템이다.
그러나 내부 실행 모델은 실제 런타임 관점에서 바라보지 않으면 추상적으로
느껴질 수 있다.

노드가 어떻게 요청되고, 프로비저닝되며, 사용되고, 정리·삭제되는지를
추적하면서 Zuul 프로세스의 흐름을 이해하고자 한다.

## 2. 시스템 구조: node는 어디에 위치하는가

Zuul의 주요 구성 요소는 다음과 같다:

-   Scheduler (Control Plane)
-   Merger (Speculative Git 상태 생성)
-   Executor (job 실행)
-   Launcher (node Provisioning 담당)
-   ZooKeeper (분산 이벤트 큐 및 상태 머신 저장, 조정)
-   SQL Database (빌드 이력 저장)
-   외부 코드 리뷰 시스템 (예: Gerrit)

Zuul 프로세스의 개념적 흐름은 다음과 같다:

    Event
      → Scheduler
        → job Graph
          → node Request
            → node Provision
              → Executor 연결
                → job 실행
                  → Cleanup
                    → node 삭제

## 3. node lifecycle의 상태 전이 모델

Zuul에서의 node는 일회성 연산 단위로 Ephemeral node 모델을 따른다.

이로 인해 다음과 같은 효과를 얻을 수 있다:

-   Secret 잔존 방지
-   상태 오염 방지
-   재현성 보장

node lifecycle은 다음과 같은 상태 모델로 이해할 수 있다:
```
state:    
    INIT
      → BUILDING
          → READY
              → IN_USE
                  → USED / HOLD
                      → DELETING
                        → DELETED
          → FAILED
            → DELETING
                → DELETED
```
각 상태 전이는 이벤트 기반이며, ZooKeeper를 통해 조정된다.

## 4. nodeset - job이 요구하는 실행 환경 정의

Zuul에서 job은 직접 node를 요청하지 않고 nodeset을 정의한다.
nodeset은 job의 실행 환경을 추상화한 객체로, job이 ansible을 실행하기 위해 필요로 하는 노드들의 집합을 의미한다.

nodeset은 다음과 같은 정보를 포함한다:

-   노드의 이름
-   노드에 필요한 label
-   노드의 역할 (예: controller, worker 등)

예시:
```
nodeset: 
    nodes: 
        - name: controller
            label: ubuntu-22.04 
        - name: worker
            label: ubuntu-22.04
```
이 경우와 같이 job은 단일 노드가 아니라 두 개 이상의 노드를 동시에
요구하기도 한다.

## 5. node Request 생성 - Scheduler

Scheduler는 job을 실행하기 위해 nodeset을 기반으로 nodeRequest를
생성한다.

node Request는 하나의 객체로, nodeset이라는 추상화된 실행 환경을 실제
리소스로 변환하는 요청이다.

node Request는 다음과 같은 상태 모델을 가진다:
```
 state:
    REQUESTED
        → PENDING
            → FULFILLED
            → FAILED
```

request 객체를 생성하여 Zookeeper에 전송하는 Scheduler 코드 일부:
```
#zuul/nodepool.py
def requestnodes(self, build_set, job, relative_priority):
    # Create a copy of the nodeset to represent the actual nodes 
    # returned by nodepool. 
    nodeset = job.nodeset.copy() 
    req = model.nodeRequest(self.sched.hostname, build_set, job,
                            nodeset,relative_priority)
    self.requests[req.uid] = req

    if nodeset.nodes:
        self.sched.zk.submitnodeRequest(req, self._updatenodeRequest)
        # Logged after submission so that we have the request id
        self.log.info("Submitted node request %s" % (req,))
        self.emitStats(req)
    else:
        self.log.info("Fulfilling empty node request %s" % (req,))
        req.state = model.STATE_FULFILLED
        self.sched.onnodesProvisioned(req)
        del self.requests[req.uid]
    return req
```
1.  Scheduler가 프로젝트 설정 평가
2.  job 실행 순서에 대한 DAG(Directed Acyclic Graph) 생성
3.  DAG의 각 job에 대해 node Request 생성

-   이 시점에 아직 실제 node는 존재하지 않음

## 6. 리소스 할당 (Provisioning) - Launcher

Launcher 컴포넌트는 node Request를 감시하여 리소스를 할당한다:

1. Zookeeper에 저장된 node request 감시 :
```
requests = sorted(self.zk.nodeRequestIterator(), key=_sort_key)

if req.state != zk.REQUESTED:
    continue
```
2. zk lock 획득: 분산 시스템 안정성 유지
```
self.zk.locknodeRequest(req, blocking=False)
```
3. ProviderManager를 통한 프로비저닝
```
rh = pm.getRequestHandler(self, req)
rh.run()
```
이 과정에서 실제 node가 생성된다.
생성된 node의 상태와 정보는 ZooKeeper를 통해 추적되고 제공된다.

4. 각 객체의 상태 변환
```
nodeRequest: REQUESTED → PENDING → FULFILLED / FAILED
node: INIT → BUILDING → READY
```

## 7. Executor 연결

node가 READY 상태가 되면:

1.  Executor가 ZooKeeper가 제공하는 node에 대한 정보를 기반으로 ansible
    inventory 생성.

2. ssh-agent 실행, 이후 해당 agent를 이용하여 ansible이 node와 연결
```
#zuul/executor/server.py
class SshAgent(object):
    def __init__(self, zuul_event_id=None, build=None):
        self.env = {}
        self.ssh_agent = None
        self.log = get_annotated_logger(
                logging.getLogger(\"zuul.ExecutorServer\"),
                zuul_event_id, build=build)
```
3.  Secret 주입

4. Ansible Playbook 실행
```
#zuul/executor/server.py
cmd = [self.executor_server.ansible_manager.getAnsibleCommand(
    ansible_version), verbose, playbook.path\]

result, code = self.runAnsible(
    cmd, timeout, playbook, ansible_version)
```
## 8. Speculative Execution과 node 증폭 효과

변경사항 큐가 다음과 같다고 가정하자:

    A → B → C

Zuul은 변경사항을 테스트하기 위해 merge된 것으로 가정한 다음 상태를
병렬로 평가한다:

    State1 = base + A
    State2 = base + A + B
    State3 = base + A + B + C

각 speculative state는 독립적인 job DAG를 실행한다.

이때 A가 실패할 경우:

1.  B와 C의 speculative state 무효화.
2.  실행 중이던 job 취소.
3.  관련 node는 Cleanup 단계로 진입.
4.  Scheduler는 Queue 재구성 (B → C)
5.  B, B+C를 위한 새로운 node Request.

이로 인해 병렬로 한번에 진행되는 평가가 많아질수록 node 수요가 증가하고
상위 변경 빌드의 실패가 많아질수록 node 수요가 급격하게 증가한다.

## 9. Pipeline Window - speculative 폭 제어 메커니즘

Zuul에서는 Pipeline Window라는 병렬 테스트에 사용되는 리소스의 양을
제어하는 장치를 제공한다.

Pipeline Window는 한번에 진행되는 Speculative Execution의 수를 제한하는
방법으로 리소스 수요를 제어한다.
예를 들어 window크기를 3으로 제한할 경우,


    큐가 A → B → C → D → E 일 때

    State1 = base + A
    State2 = base + A + B
    State3 = base + A + B + C
    State4 = base + A + B + C + D
    State5 = base + A + B + C + D + E

가 아닌 :

    State1 = base + A
    State2 = base + A + B
    State3 = base + A + B + C

를 우선 실행하고 각 작업이 완료될 때마다 뒤에 남은 D, E를 앞으로
가져와서 추가적으로 실행하게 된다. 따라서 실패로 인해 새로운 리소스를
요청할 경우 낭비되는 리소스가 줄어드는 효과를 볼 수 있다.

## 10. Cleanup

job 완료 후:

1.  Artifact 업로드
2.  Log 스트리밍

3. Cleanup 루틴 실행
```
pm = self._nodepool.getProviderManager(node.provider)
pm.startnodeCleanup(node)
```
4.  node: Used → DELETING 상태 전이
5.  리소스 제거
