export const FIREBASE_PROJECTS = Object.freeze({
  production: 'tudo-aqui-macacu',
  beta: 'macacu-beta-261030-cf4a81',
});

export function isSupportedFirebaseProject(projectId) {
  return Object.values(FIREBASE_PROJECTS).includes(projectId);
}
