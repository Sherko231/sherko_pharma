import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../application/catalog_search_controller.dart';
import '../data/catalog_draft_store.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_product.dart';
import '../domain/catalog_product_id.dart';
import '../domain/catalog_product_input.dart';

class CatalogProductFormScreen extends ConsumerStatefulWidget {
  const CatalogProductFormScreen.create({super.key}) : product = null;

  const CatalogProductFormScreen.edit({
    required this.product,
    super.key,
  });

  final CatalogProduct? product;

  bool get isCreate => product == null;

  @override
  ConsumerState<CatalogProductFormScreen> createState() =>
      _CatalogProductFormScreenState();
}

enum _ExitChoice {
  save,
  discard,
  stay,
}

enum _ConflictChoice {
  useServer,
  overwrite,
  stay,
}

class _CatalogProductFormScreenState
    extends ConsumerState<CatalogProductFormScreen> {
  late final TextEditingController _nameEnController;
  late final TextEditingController _nameArController;
  late final TextEditingController _compositionController;
  late final TextEditingController _manufacturerController;
  late final TextEditingController _strengthController;
  late final TextEditingController _dosageFormController;
  late final TextEditingController _packageController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _barcode2Controller;
  late final TextEditingController _sellingAmountController;
  late final TextEditingController _notesController;

  late CatalogProductFormData _baseline;
  CatalogProduct? _baseProduct;
  late String _createProductId;
  late final String _draftScopeKey;
  String _currency = 'SYP';

  CatalogProductFormValidation _validation =
      const CatalogProductFormValidation({});
  CatalogProduct? _latestConflict;
  CatalogProductInput? _pendingInput;
  CatalogProduct? _pendingBase;
  bool _saving = false;
  bool _uncertain = false;
  bool _allowPop = false;
  bool _exitDialogOpen = false;
  bool _draftReady = false;
  bool _draftRestored = false;
  String? _ownerId;
  String? _saveError;
  String? _draftError;
  Timer? _draftTimer;
  Future<void> _draftIo = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _baseProduct = widget.product;
    _baseline = widget.product == null
        ? const CatalogProductFormData.empty()
        : CatalogProductFormData.fromProduct(widget.product!);
    _createProductId = widget.product?.id ?? generateCatalogProductId();
    _draftScopeKey = widget.product == null
        ? 'create'
        : 'edit:${widget.product!.id}';

    _nameEnController = TextEditingController(text: _baseline.nameEn);
    _nameArController = TextEditingController(text: _baseline.nameAr);
    _compositionController =
        TextEditingController(text: _baseline.composition);
    _manufacturerController =
        TextEditingController(text: _baseline.manufacturer);
    _strengthController = TextEditingController(text: _baseline.strength);
    _dosageFormController =
        TextEditingController(text: _baseline.dosageForm);
    _packageController =
        TextEditingController(text: _baseline.packageDescription);
    _barcodeController = TextEditingController(text: _baseline.barcode);
    _barcode2Controller = TextEditingController(text: _baseline.barcode2);
    _sellingAmountController =
        TextEditingController(text: _baseline.sellingAmountText);
    _notesController = TextEditingController(text: _baseline.notes);
    _currency = _baseline.currency;
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _nameEnController.dispose();
    _nameArController.dispose();
    _compositionController.dispose();
    _manufacturerController.dispose();
    _strengthController.dispose();
    _dosageFormController.dispose();
    _packageController.dispose();
    _barcodeController.dispose();
    _barcode2Controller.dispose();
    _sellingAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  CatalogProductFormData get _currentData => CatalogProductFormData(
        nameEn: _nameEnController.text,
        nameAr: _nameArController.text,
        composition: _compositionController.text,
        manufacturer: _manufacturerController.text,
        strength: _strengthController.text,
        dosageForm: _dosageFormController.text,
        packageDescription: _packageController.text,
        barcode: _barcodeController.text,
        barcode2: _barcode2Controller.text,
        sellingAmountText: _sellingAmountController.text,
        currency: _currency,
        notes: _notesController.text,
      );

  bool get _dirty => _currentData != _baseline;

  bool get _fieldsEnabled => _draftReady && !_saving && !_uncertain;

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.isCreate;

    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _requestExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isCreate ? 'New product' : 'Edit product'),
          actions: [
            TextButton(
              key: const Key('product-save'),
              onPressed: !_draftReady || _saving || _uncertain ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                key: const Key('product-form'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  if (!_draftReady) ...[
                    const _StatusCard(
                      key: Key('product-draft-loading'),
                      icon: Icons.restore,
                      title: 'Restoring local draft',
                      message: 'Checking this device for unfinished product input.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_draftRestored) ...[
                    const _StatusCard(
                      key: Key('product-draft-restored'),
                      icon: Icons.restore_page,
                      title: 'Unsaved draft restored',
                      message: 'These values are local only. Nothing was sent to the server.',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_draftError != null) ...[
                    _StatusCard(
                      key: const Key('product-draft-error'),
                      icon: Icons.save_outlined,
                      title: 'Draft is not safely stored',
                      message: _draftError!,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_uncertain) ...[
                    _StatusCard(
                      key: const Key('product-save-uncertain'),
                      icon: Icons.help_outline,
                      title: 'Save status is unknown',
                      message:
                          'Do not retry the write yet. Check the server first so a product is not duplicated or overwritten.',
                      action: FilledButton.tonal(
                        key: const Key('product-check-save-status'),
                        onPressed: _saving ? null : _checkUncertainStatus,
                        child: const Text('Check save status'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_latestConflict != null) ...[
                    _StatusCard(
                      key: const Key('product-conflict'),
                      icon: Icons.sync_problem,
                      title: 'Product changed on the server',
                      message:
                          'Your input is still here. Resolve the conflict before saving over the newer revision.',
                      action: FilledButton.tonal(
                        key: const Key('product-resolve-conflict'),
                        onPressed: _saving ? null : _resolveConflict,
                        child: const Text('Resolve conflict'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_saveError != null) ...[
                    _StatusCard(
                      key: const Key('product-save-error'),
                      icon: Icons.error_outline,
                      title: 'Product was not saved',
                      message: _saveError!,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Names',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    key: const Key('product-field-name-en'),
                    controller: _nameEnController,
                    label: 'English name',
                    errorText: _validation['names'],
                  ),
                  _field(
                    key: const Key('product-field-name-ar'),
                    controller: _nameArController,
                    label: 'Arabic name',
                    errorText: _validation['names'],
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Product information',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    key: const Key('product-field-composition'),
                    controller: _compositionController,
                    label: 'Composition / active ingredients',
                    maxLines: 2,
                  ),
                  _field(
                    key: const Key('product-field-manufacturer'),
                    controller: _manufacturerController,
                    label: 'Manufacturer / company',
                  ),
                  _field(
                    key: const Key('product-field-strength'),
                    controller: _strengthController,
                    label: 'Strength',
                  ),
                  _field(
                    key: const Key('product-field-dosage-form'),
                    controller: _dosageFormController,
                    label: 'Dosage form',
                  ),
                  _field(
                    key: const Key('product-field-package'),
                    controller: _packageController,
                    label: 'Package description',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Barcodes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    key: const Key('product-field-barcode'),
                    controller: _barcodeController,
                    label: 'Primary barcode',
                  ),
                  _field(
                    key: const Key('product-field-barcode2'),
                    controller: _barcode2Controller,
                    label: 'Secondary barcode',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selling price',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final priceField = _field(
                        key: const Key('product-field-selling-amount'),
                        controller: _sellingAmountController,
                        label: 'Whole-unit amount',
                        errorText: _validation['sellingAmount'],
                        keyboardType: TextInputType.number,
                      );
                      final currencyField = _currencyField();

                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [
                            priceField,
                            currencyField,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: priceField),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 180,
                            child: currencyField,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    key: const Key('product-field-notes'),
                    controller: _notesController,
                    label: 'Notes',
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? errorText,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextDirection? textDirection,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: controller,
        enabled: _fieldsEnabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textDirection: textDirection,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _formChanged(),
      ),
    );
  }

  Widget _currencyField() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Currency',
        errorText: _validation['currency'],
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('product-field-currency'),
          value: _currency,
          isExpanded: true,
          onChanged: _fieldsEnabled
              ? (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _currency = value;
                    _validation = const CatalogProductFormValidation({});
                    _saveError = null;
                  });
                  _scheduleDraftPersistence();
                }
              : null,
          items: CatalogProductFormData.supportedCurrencies
              .map(
                (currency) => DropdownMenuItem(
                  value: currency,
                  child: Text(currency),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  void _formChanged() {
    setState(() {
      _validation = const CatalogProductFormValidation({});
      _saveError = null;
    });
    _scheduleDraftPersistence();
  }

  Future<void> _restoreDraft() async {
    final ownerId = ref.read(authControllerProvider).identity?.userId;
    _ownerId = ownerId;

    if (ownerId == null) {
      if (mounted) {
        setState(() {
          _draftReady = true;
          _draftError = 'Sign in again before using local draft storage.';
        });
      }
      return;
    }

    try {
      final draft = await ref.read(catalogDraftStoreProvider).load(
            ownerId: ownerId,
            scopeKey: _draftScopeKey,
          );

      if (!mounted) {
        return;
      }

      if (draft != null) {
        if (widget.isCreate) {
          if (draft.baseProduct != null) {
            throw const CatalogDraftStorageException();
          }
          _baseline = const CatalogProductFormData.empty();
          _baseProduct = null;
        } else {
          final draftBase = draft.baseProduct;
          if (draftBase == null || draftBase.id != widget.product!.id) {
            throw const CatalogDraftStorageException();
          }
          _baseProduct = draftBase;
          _baseline = CatalogProductFormData.fromProduct(draftBase);
        }

        _createProductId = draft.productId;
        _populate(draft.formData);
        _uncertain = draft.uncertain;
        _pendingBase = draft.pendingBase;
        if (_uncertain) {
          final validation = draft.formData.validate();
          if (!validation.isValid ||
              (!widget.isCreate && _pendingBase == null)) {
            _uncertain = false;
            _pendingBase = null;
            _draftError =
                'The previous save state could not be reconciled safely. Review the restored input before saving.';
          } else {
            _pendingInput = draft.formData.toInput();
          }
        }
        _draftRestored = true;
      }

      setState(() {
        _draftReady = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _draftReady = true;
          _draftError =
              'The local draft could not be restored safely. No server write was attempted.';
        });
      }
    }
  }

  void _scheduleDraftPersistence() {
    if (!_draftReady || _ownerId == null) {
      return;
    }

    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistDraftNow());
    });
  }

  Future<bool> _persistDraftNow() async {
    final ownerId = _ownerId;
    if (!_draftReady || ownerId == null) {
      return false;
    }

    _draftTimer?.cancel();
    if (!_dirty && !_uncertain) {
      return _clearDraft();
    }

    final draft = CatalogProductDraft(
      ownerId: ownerId,
      scopeKey: _draftScopeKey,
      productId: _createProductId,
      formData: _currentData,
      baseProduct: widget.isCreate ? null : _baseProduct,
      uncertain: _uncertain,
      pendingBase: _uncertain ? _pendingBase : null,
    );

    return _runDraftOperation(
      () => ref.read(catalogDraftStoreProvider).save(draft),
    );
  }

  Future<bool> _clearDraft() async {
    final ownerId = _ownerId;
    if (ownerId == null) {
      return false;
    }

    _draftTimer?.cancel();
    return _runDraftOperation(
      () => ref.read(catalogDraftStoreProvider).clear(
            ownerId: ownerId,
            scopeKey: _draftScopeKey,
          ),
    );
  }

  Future<bool> _runDraftOperation(Future<void> Function() action) async {
    final previous = _draftIo.catchError((_) {});
    final operation = previous.then((_) => action());
    _draftIo = operation.catchError((_) {});

    try {
      await operation;
      if (mounted && _draftError != null) {
        setState(() {
          _draftError = null;
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _draftError =
              'Local draft storage failed. Keep this form open until the draft can be stored or the server save is confirmed.';
        });
      }
      return false;
    }
  }

  Future<void> _save() async {
    if (_saving || _uncertain) {
      return;
    }

    if (_latestConflict != null) {
      await _resolveConflict();
      return;
    }

    final data = _currentData;
    final validation = data.validate();
    if (!validation.isValid) {
      setState(() {
        _validation = validation;
        _saveError = null;
      });
      return;
    }

    final input = data.toInput();
    final base = _baseProduct;

    if (base != null && input.matchesProduct(base)) {
      if (await _clearDraft()) {
        await _leaveWithResult(base);
      }
      return;
    }

    await _persistDraftNow();

    setState(() {
      _saving = true;
      _validation = validation;
      _saveError = null;
    });

    final repository = ref.read(catalogRepositoryProvider);
    final result = base == null
        ? await repository.create(
            productId: _createProductId,
            input: input,
          )
        : await repository.update(
            original: base,
            input: input,
          );

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });

    await _handleSaveResult(
      result,
      input: input,
      base: base,
    );
  }

  Future<void> _handleSaveResult(
    CatalogSaveResult result, {
    required CatalogProductInput input,
    required CatalogProduct? base,
  }) async {
    switch (result) {
      case CatalogSaveConfirmed(:final product):
        _baseProduct = product;
        _baseline = CatalogProductFormData.fromProduct(product);
        _latestConflict = null;
        _pendingInput = null;
        _pendingBase = null;
        _uncertain = false;
        if (await _clearDraft()) {
          await _leaveWithResult(product);
        }
      case CatalogSaveRejected():
        setState(() {
          _saveError =
              'The server did not confirm this save. You can retry safely.';
          _uncertain = false;
          _pendingInput = null;
          _pendingBase = null;
        });
        await _persistDraftNow();
      case CatalogSaveConflict(:final latest):
        setState(() {
          _latestConflict = latest;
          _saveError = latest == null
              ? 'A newer server revision exists, but it could not be loaded yet.'
              : null;
          _uncertain = false;
          _pendingInput = null;
          _pendingBase = null;
        });
        await _persistDraftNow();
        if (latest != null && base != null) {
          await _showConflictDialog();
        }
      case CatalogSaveUncertain():
        setState(() {
          _uncertain = true;
          _pendingInput = input;
          _pendingBase = base;
          _saveError = null;
        });
        await _persistDraftNow();
      case CatalogSaveMissing():
        setState(() {
          _saveError = 'This product no longer exists on the server.';
          _uncertain = false;
          _pendingInput = null;
          _pendingBase = null;
        });
        await _persistDraftNow();
    }
  }

  Future<void> _checkUncertainStatus() async {
    final input = _pendingInput;
    if (!_uncertain || input == null || _saving) {
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final repository = ref.read(catalogRepositoryProvider);
    final base = _pendingBase;
    final result = base == null
        ? await repository.reconcileCreate(
            productId: _createProductId,
            input: input,
          )
        : await repository.reconcileUpdate(
            original: base,
            input: input,
          );

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });

    await _handleSaveResult(
      result,
      input: input,
      base: base,
    );
  }

  Future<void> _resolveConflict() async {
    var latest = _latestConflict;
    final base = _baseProduct;

    if (base == null) {
      setState(() {
        _saveError =
            'The generated product identity conflicts with an existing row. Close this form and start a new product.';
      });
      return;
    }

    if (latest == null) {
      setState(() {
        _saving = true;
        _saveError = null;
      });
      try {
        latest = await ref.read(catalogRepositoryProvider).getById(base.id);
      } catch (_) {
        if (mounted) {
          setState(() {
            _saving = false;
            _saveError =
                'Could not load the latest server version. Check the connection and try again.';
          });
        }
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _latestConflict = latest;
      });
    }

    await _showConflictDialog();
  }

  Future<void> _showConflictDialog() async {
    final latest = _latestConflict;
    if (latest == null || !mounted) {
      return;
    }

    final choice = await showDialog<_ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('product-conflict-dialog'),
          title: const Text('Resolve product conflict'),
          content: Text(
            'The server has revision ${latest.revision}. '
            'Use that version, keep reviewing your local changes, or explicitly overwrite it with your current form values.',
          ),
          actions: [
            TextButton(
              key: const Key('conflict-stay'),
              onPressed: () {
                Navigator.of(dialogContext).pop(_ConflictChoice.stay);
              },
              child: const Text('Stay'),
            ),
            TextButton(
              key: const Key('conflict-use-server'),
              onPressed: () {
                Navigator.of(dialogContext).pop(_ConflictChoice.useServer);
              },
              child: const Text('Use server version'),
            ),
            FilledButton(
              key: const Key('conflict-overwrite'),
              onPressed: () {
                Navigator.of(dialogContext).pop(_ConflictChoice.overwrite);
              },
              child: const Text('Overwrite with my changes'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null || choice == _ConflictChoice.stay) {
      return;
    }

    if (choice == _ConflictChoice.useServer) {
      _baseProduct = latest;
      _baseline = CatalogProductFormData.fromProduct(latest);
      _populate(_baseline);
      setState(() {
        _latestConflict = null;
        _saveError = null;
        _validation = const CatalogProductFormValidation({});
        _draftRestored = false;
      });
      await _clearDraft();
      return;
    }

    final data = _currentData;
    final validation = data.validate();
    if (!validation.isValid) {
      setState(() {
        _validation = validation;
      });
      return;
    }

    final input = data.toInput();
    setState(() {
      _saving = true;
      _saveError = null;
      _latestConflict = null;
    });

    final result = await ref.read(catalogRepositoryProvider).update(
          original: latest,
          input: input,
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });
    await _handleSaveResult(
      result,
      input: input,
      base: latest,
    );
  }

  void _populate(CatalogProductFormData data) {
    _nameEnController.text = data.nameEn;
    _nameArController.text = data.nameAr;
    _compositionController.text = data.composition;
    _manufacturerController.text = data.manufacturer;
    _strengthController.text = data.strength;
    _dosageFormController.text = data.dosageForm;
    _packageController.text = data.packageDescription;
    _barcodeController.text = data.barcode;
    _barcode2Controller.text = data.barcode2;
    _sellingAmountController.text = data.sellingAmountText;
    _notesController.text = data.notes;
    _currency = data.currency;
  }

  Future<void> _requestExit() async {
    if (_exitDialogOpen || _allowPop) {
      return;
    }

    if (_saving) {
      return;
    }

    if (_uncertain) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('uncertain-exit-dialog'),
          title: const Text('Check save status first'),
          content: const Text(
            'The server result is unknown. Check save status before leaving so the write can be reconciled safely.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Stay'),
            ),
          ],
        ),
      );
      return;
    }

    if (!_dirty) {
      if (await _clearDraft()) {
        await _leaveWithoutResult();
      }
      return;
    }

    _exitDialogOpen = true;
    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('unsaved-product-dialog'),
        title: const Text('Unsaved changes'),
        content: const Text(
          'Save your changes, discard them, or stay on this form.',
        ),
        actions: [
          TextButton(
            key: const Key('unsaved-stay'),
            onPressed: () {
              Navigator.of(dialogContext).pop(_ExitChoice.stay);
            },
            child: const Text('Stay'),
          ),
          TextButton(
            key: const Key('unsaved-discard'),
            onPressed: () {
              Navigator.of(dialogContext).pop(_ExitChoice.discard);
            },
            child: const Text('Discard Changes'),
          ),
          FilledButton(
            key: const Key('unsaved-save'),
            onPressed: () {
              Navigator.of(dialogContext).pop(_ExitChoice.save);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;

    if (!mounted || choice == null || choice == _ExitChoice.stay) {
      return;
    }

    if (choice == _ExitChoice.discard) {
      if (await _clearDraft()) {
        await _leaveWithoutResult();
      }
      return;
    }

    await _save();
  }

  Future<void> _leaveWithResult(CatalogProduct product) async {
    await _enablePopAndLeave(product);
  }

  Future<void> _leaveWithoutResult() async {
    await _enablePopAndLeave(null);
  }

  Future<void> _enablePopAndLeave(CatalogProduct? product) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.of(context).pop(product);
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(message),
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    action!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
