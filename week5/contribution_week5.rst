Zuul 문서 번역을 위한 Ansible module
====================================

Ansible playbook을 통한 Zuul 문서 번역에 사용한 module 정리입니다.

**Requirements**

1. Using **Shell script** to build HTML documentation

   `build-translated-lang.sh <https://github.com/openstack-kr/zuul-study/blob/main/l10n-artifact/build-translated-lang.sh>`_ 

   위 쉘 스크립트를 사용합니다. 수행하는 작업은 아래와 같습니다.

   A. virtual environment 생성
   B. venv에 dependencies 설치
   C. co 파일 컴파일을 통한 mo파일 생성
   D. 번역된 HTML파일 빌드

2. Using Zuul with **Ansible playbook**

   Zuul 환경에 Job을 추가해서 번역한 po파일을 커밋하면 번역된 HTML파일이 생성되도록 합니다.


**Ansible playbook** 번역을 위해 playbook에 포함할 작업은 다음과 같습니다.

* 파이썬 환경설정
* Zuul repository 클론
* 프로젝트의 번역된 po파일을 zuul/doc/source/locale로 복사
* 번역 문서 빌드 스크립트 실행
* 결과물(HTML) 가져오기


**Ansible module** 위 playbook 작성에 사용한 module들 입니다.

* ansible.builtin.shell

  .. code-block:: yaml

     ansible.builtin.shell: |
         export DEBIAN_FRONTEND=noninteractive
         apt-get update
         apt-get install -y software-properties-common gnupg gnupg2
         add-apt-repository -y ppa:deadsnakes/ppa
         apt-get update
         apt-get install -y gettext python3.11 python3.11-venv python3.11-dev graphviz fonts-nanum

* ansible.builtin.git

  .. code-block:: yaml

     ansible.builtin.git:
        repo: 'https://opendev.org/zuul/zuul.git'
        dest: "{{ ansible_user_dir }}/zuul-repo"

* ansible.builtin.copy

  .. code-block:: yaml

     ansible.builtin.copy:
        src: "{{ zuul.project.src_dir }}/l10n-artifact/build-translated-lang.sh"
        dest: "{{ zuul_doc_path }}/build-translated-lang.sh"
        mode: '0755'
        remote_src: yes

  .. code-block:: yaml

     ansible.builtin.copy:
        src: "{{ zuul.project.src_dir }}/l10n-artifact/ko_KR"
        dest: "{{ zuul_doc_path }}/source/locale/"
        remote_src: yes


* ansible.builtin.file

  .. code-block:: yaml

     ansible.builtin.file:
        path: "{{ zuul_doc_path }}/source/locale"
        state: directory

  .. code-block:: yaml

     ansible.builtin.file:
        path: "{{ ansible_user_dir }}/zuul-repo/venv"
        state: absent


* ansible.builtin.command

  .. code-block:: yaml

     ansible.builtin.command: "bash {{ zuul_doc_path }}/build-translated-lang.sh ko_KR"
      args:
        chdir: "{{ zuul_doc_path }}"

* ansible.posix.synchronize

  .. code-block:: yaml

     ansible.posix.synchronize:
        src: "{{ zuul_doc_path }}/build/html/ko_KR/"
        dest: "{{ zuul.executor.log_root }}/html_docs/"
        mode: pull

