Zuul Project Gating Experiment
========================================

Experimenting Project Gating of Zuul 

`Zuul Project Gating <https://zuul-ci.org/docs/zuul/latest/gating.html>`_


will reuse test1 project and configuration files from `Zuul Tutorial <https://zuul-ci.org/docs/zuul/latest/tutorials/quick-start.html>`_


Testing in Parallel
----------------------

**Add Conditional Job**

1. **.zuul.yaml**
   Add conditional job for gate pipeline.

   .. code-block:: yaml

      - job:
          name: testjob
          run: playbooks/testjob.yaml

      - job:
          name: gating-test-job
          run: playbooks/conditional_job.yaml

      - project:
          check:
            jobs:
              - testjob
          gate:
            jobs:
              - gating-test-job

2. **conditional_job.yaml**
   Check Commit message to fail or not

   .. code-block:: yaml

      # playbooks/conditional_job.yaml
      - hosts: all
        tasks:
          - name: Wait for observation
            ansible.builtin.pause:
              seconds: 15
          - name: Conditional failure
            fail:
              msg: "Gating failed because FAILME keyword was found"
            when: "zuul.message is defined and 'FAILME' in zuul.message"
          - name: Otherwise succeed
            debug:
              msg: "This PR passed the conditional test!"
            when: "zuul.message is defined and 'FAILME' not in zuul.message"

3. **Send multiple reviews**
   See what happens after intermediate commit fails


Cross Project Testing
------------------------

Cross-Project Dependencies
-----------------------------

Dependent Pipeline
-----------------------------


Independent Pipeline
-----------------------------
