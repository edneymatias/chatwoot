import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from '../../../helper/URLHelper';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
  featureFlag: FEATURE_FLAGS.SCOUT,
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/scout'),
    component: () => import('./pages/ScoutList.vue'),
    name: 'scouts_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/tools'),
    component: () => import('./pages/ScoutToolsList.vue'),
    name: 'scout_tools',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId'),
    component: () => import('./pages/ScoutDetail.vue'),
    name: 'scout_detail',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId/inboxes'),
    component: () => import('./pages/ScoutDetail.vue'),
    name: 'scout_inboxes',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId/products'),
    component: () => import('./pages/ScoutDetail.vue'),
    name: 'scout_products',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId/knowledge'),
    component: () => import('./pages/ScoutDetail.vue'),
    name: 'scout_knowledge',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId/funnel'),
    component: () => import('./pages/ScoutDetail.vue'),
    name: 'scout_funnel',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/scout/:scoutId/playground'),
    component: () => import('./pages/ScoutPlayground.vue'),
    name: 'scout_playground',
    meta,
  },
];

export default {
  routes,
};
