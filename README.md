# Equation Contracts

**Equation Contracts** is a collection of smart contracts for perpetual contracts.

## Local Development

To compile the contracts locally, follow these steps:

1. Clone the repository:

```shell
git clone git@github.com:EquationDAO/equation-contracts.git
```

2. Install the required dependencies:

```shell
npm install
```

3. Install husky hooks:

```shell
npm run prepare
```

4. Compile the contracts:

```shell
npm run build
```

## Deployment Addresses

The **Equation Contracts** project is deployed to the following networks:

| Network          | Chain ID | Contracts                        |
| ---------------- | -------- | -------------------------------- |
| Arbitrum Mainnet | 42161    | [View](./deployments/42161.json) |

## License

The **Equation Contracts** project uses a variety of open-source licenses for its codebase. The licensing details for
each portion of the project can be found in the individual source code files via the `SPDX-License-Identifier` header.
Here is a summary of the licensing information for different parts of the project:

1. Code under the `./contracts/**/interfaces` directory is licensed under the GPL-2.0 license.
2. Third-party code used in the project is subject to the following licenses:
    - MIT License
    - GPL-2.0 License
3. Code under the `./contracts/test` directory is not licensed for use outside of the **Equation Contracts** project.
4. All other code in the project is licensed under the BSL-1.1 license.
