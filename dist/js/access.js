export const roleNames = { employee: 'Employee', manager: 'Manager', finance: 'Finance Administrator', admin: 'Administrator' };
export const roleHomes = { employee: 'employee-dashboard.html', manager: 'manager-dashboard.html', finance: 'finance-dashboard.html', admin: 'admin.html' };
export const routeRules = { 'employee-dashboard': ['employee'], 'submit-expense': ['employee'], 'manager-dashboard': ['manager'], 'finance-dashboard': ['finance'], admin: ['admin'], 'reimbursement-tickets': ['employee', 'finance', 'admin'] };
export function homeFor(role) { return roleHomes[role] || 'login.html'; }
export function mayOpen(route, role) { return !!roleHomes[role] && (!routeRules[route] || routeRules[route].includes(role)); }
export function requestedRole(value) { return ['employee', 'manager', 'finance'].includes(value) ? value : 'employee'; }
