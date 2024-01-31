import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  tags: {
    // Important for the dashboard to work properly
    testid: __ENV.CLOUD_RUN_EXECUTION,
    taskId: __ENV.CLOUD_RUN_TASK_INDEX + '-' + __ENV.CLOUD_RUN_TASK_ATTEMPT,
  },

  duration: '30s',
  vus: 100,
};


// The function that defines VU logic.
//
// See https://grafana.com/docs/k6/latest/examples/get-started-with-k6/ to learn more
// about authoring k6 scripts.
//
export default function () {
  const r = http.get('https://test.k6.io');
  sleep(1);
}
