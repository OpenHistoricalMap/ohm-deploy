describe('empty spec', () => {
  it('passes', () => {
    cy.visit('https://staging.openhistoricalmap.org/login');
    // cy.get('.login-menu > a').first().should('exist').click();
    cy.get('#username').should('exist').type('testuser');
    cy.get('#password').should('exist').type('mypassword');
    cy.get('input[value=Login]').first().should('exist').click();
    // cy.location().should((loc) => {
    //   expect(loc.pathname).to.eq('/login');

    // });

  })
})