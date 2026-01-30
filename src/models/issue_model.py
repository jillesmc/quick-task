"""
Modelo de dados para o formulário de criação de issues
Expõe propriedades observáveis para QML
"""

from pathlib import Path
import sys
from datetime import datetime
from typing import Optional, List

from PySide6.QtCore import QObject, Property, Signal, QDateTime, Slot  # type: ignore[import]

# Adicionar diretório raiz ao path para importar config
ROOT_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(ROOT_DIR))

from config.config_manager import ConfigManager


class IssueModel(QObject):
    """Modelo de dados para o formulário de criação de issues"""

    # Signals para notificar mudanças
    summaryChanged = Signal(str)
    descriptionChanged = Signal(str)
    tipoAtividadeChanged = Signal(str)
    statusInicialChanged = Signal(str)
    documentacaoAnexaChanged = Signal(str)
    utilizacaoIAChanged = Signal(str)
    valorEntregueChanged = Signal(str)
    plataformasAfetadasChanged = Signal(list)
    registrarWorklogChanged = Signal(bool)
    worklogInicioChanged = Signal(str)  # String para QML
    worklogDuracaoChanged = Signal(int)
    tipoAtividadeValuesChanged = Signal()
    statusSequenceChanged = Signal()
    valorEntregueValuesChanged = Signal()
    plataformasAfetadasValuesChanged = Signal()
    epicParentKeyChanged = Signal(str)
    epicParentSummaryChanged = Signal(str)

    def __init__(self, parent=None):
        """Inicializa o modelo com valores padrão"""
        super().__init__(parent)

        # Carregar configuração
        try:
            from src.utils.debug import debug_log

            debug_log("IssueModel", "__init__", "Carregando configuração...")
            self._config = ConfigManager()
            debug_log("IssueModel", "__init__", "Configuração carregada com sucesso")
            # Emitir sinais para propriedades read-only após carregar config
            self.tipoAtividadeValuesChanged.emit()
            self.statusSequenceChanged.emit()
        except Exception as e:
            print(f"Erro ao carregar configuração: {e}", file=sys.stderr)
            self._config = None

        # Valores padrão
        self._summary = ""
        self._description = ""

        # Tipo de atividade padrão: "Suporte Dúvidas/Suporte uso incorreto"
        tipo_atividade_values = self.tipoAtividadeValues
        default_tipo = "Suporte Dúvidas/Suporte uso incorreto"
        if default_tipo not in tipo_atividade_values:
            default_tipo = tipo_atividade_values[0] if tipo_atividade_values else ""
        self._tipoAtividade = default_tipo

        # Status inicial padrão: primeiro status da sequência (geralmente "TO DO")
        status_sequence = self.statusSequence
        default_status = status_sequence[0] if status_sequence else "TO DO"
        self._statusInicial = default_status

        self._documentacaoAnexa = "Não"
        self._utilizacaoIA = "Não"

        # Valor Entregue e Plataformas afetadas
        valor_entregue_values = self.valorEntregueValues
        self._valorEntregue = valor_entregue_values[0] if valor_entregue_values else ""
        self._plataformasAfetadas: List[str] = []

        # Worklog padrão
        self._registrarWorklog = False
        # Data/hora atual como padrão
        now = datetime.now()
        self._worklogInicio = QDateTime.fromString(
            now.strftime("%Y-%m-%d %H:%M:%S"), "yyyy-MM-dd HH:mm:ss"
        )
        self._worklogDuracao = 30  # 30 minutos como padrão
        self._worklogComment: str = ""

        # Epic parent (opcional)
        self._epicParentKey: str = ""
        self._epicParentSummary: str = ""

    def get_worklog_inicio_datetime(self) -> Optional[datetime]:
        """Retorna worklogInicio como datetime Python para uso interno"""
        if self._worklogInicio and self._worklogInicio.isValid():
            return datetime(
                self._worklogInicio.date().year(),
                self._worklogInicio.date().month(),
                self._worklogInicio.date().day(),
                self._worklogInicio.time().hour(),
                self._worklogInicio.time().minute(),
                self._worklogInicio.time().second(),
            )
        return None

    # Propriedade: summary
    @Property(str, notify=summaryChanged)
    def summary(self):
        return self._summary

    @summary.setter
    def summary(self, value: str):
        if self._summary != value:
            self._summary = value
            self.summaryChanged.emit(value)

    # Propriedade: description
    @Property(str, notify=descriptionChanged)
    def description(self):
        return self._description

    @description.setter
    def description(self, value: str):
        if self._description != value:
            self._description = value
            self.descriptionChanged.emit(value)

    # Propriedade: tipoAtividade
    @Property(str, notify=tipoAtividadeChanged)
    def tipoAtividade(self):
        return self._tipoAtividade

    @tipoAtividade.setter
    def tipoAtividade(self, value: str):
        if self._tipoAtividade != value:
            self._tipoAtividade = value
            self.tipoAtividadeChanged.emit(value)

    # Propriedade: statusInicial
    @Property(str, notify=statusInicialChanged)
    def statusInicial(self):
        return self._statusInicial

    @statusInicial.setter
    def statusInicial(self, value: str):
        if self._statusInicial != value:
            self._statusInicial = value
            self.statusInicialChanged.emit(value)

    # Propriedade: documentacaoAnexa
    @Property(str, notify=documentacaoAnexaChanged)
    def documentacaoAnexa(self):
        return self._documentacaoAnexa

    @documentacaoAnexa.setter
    def documentacaoAnexa(self, value: str):
        if self._documentacaoAnexa != value:
            self._documentacaoAnexa = value
            self.documentacaoAnexaChanged.emit(value)

    # Propriedade: utilizacaoIA
    @Property(str, notify=utilizacaoIAChanged)
    def utilizacaoIA(self):
        return self._utilizacaoIA

    @utilizacaoIA.setter
    def utilizacaoIA(self, value: str):
        if self._utilizacaoIA != value:
            self._utilizacaoIA = value
            self.utilizacaoIAChanged.emit(value)

    # Propriedade: tipoAtividadeValues (read-only)
    # Nota: Usando read-only com notify para compatibilidade
    @Property(list, notify=tipoAtividadeValuesChanged)
    def tipoAtividadeValues(self):
        """Retorna lista de valores para tipo de atividade"""
        if self._config:
            return self._config.get_tipo_atividade_values()
        return []

    # Propriedade: statusSequence (read-only)
    # Nota: Usando read-only com notify para compatibilidade
    @Property(list, notify=statusSequenceChanged)
    def statusSequence(self):
        """Retorna sequência de status"""
        if self._config:
            return self._config.get_status_sequence()
        return []

    # Propriedade: registrarWorklog
    @Property(bool, notify=registrarWorklogChanged)
    def registrarWorklog(self):
        return self._registrarWorklog

    @registrarWorklog.setter
    def registrarWorklog(self, value: bool):
        if self._registrarWorklog != value:
            self._registrarWorklog = value
            self.registrarWorklogChanged.emit(value)

    # Propriedade: worklogInicio (como string para QML)
    @Property(str, notify=worklogInicioChanged)
    def worklogInicio(self):
        if self._worklogInicio:
            return self._worklogInicio.toString("yyyy-MM-dd HH:mm:ss")
        return ""

    @worklogInicio.setter
    def worklogInicio(self, value: str):
        if value:
            dt = QDateTime.fromString(value, "yyyy-MM-dd HH:mm:ss")
            if dt.isValid() and self._worklogInicio != dt:
                self._worklogInicio = dt
                self.worklogInicioChanged.emit(value)

    # Propriedade: worklogDuracao
    @Property(int, notify=worklogDuracaoChanged)
    def worklogDuracao(self):
        return self._worklogDuracao

    @worklogDuracao.setter
    def worklogDuracao(self, value: int):
        if self._worklogDuracao != value:
            self._worklogDuracao = value
            self.worklogDuracaoChanged.emit(value)

    # Propriedade: worklogComment
    worklogCommentChanged = Signal(str)

    @Property(str, notify=worklogCommentChanged)
    def worklogComment(self) -> str:
        return self._worklogComment

    @worklogComment.setter
    def worklogComment(self, value: str) -> None:
        if self._worklogComment != value:
            self._worklogComment = value or ""
            self.worklogCommentChanged.emit(self._worklogComment)

    @Slot()
    def reset_to_defaults(self):
        """Reseta os campos do modelo para os valores padrão"""
        self.summary = ""
        self.description = ""

        # Resetar tipoAtividade
        tipo_atividade_values = self.tipoAtividadeValues
        default_tipo = "Suporte Dúvidas/Suporte uso incorreto"
        if default_tipo not in tipo_atividade_values:
            default_tipo = tipo_atividade_values[0] if tipo_atividade_values else ""
        self.tipoAtividade = default_tipo

        # Resetar status inicial
        status_sequence = self.statusSequence
        default_status = status_sequence[0] if status_sequence else "TO DO"
        self.statusInicial = default_status

        self.documentacaoAnexa = "Não"
        self.utilizacaoIA = "Não"

        # Resetar Valor Entregue e Plataformas afetadas
        valor_entregue_values = self.valorEntregueValues
        self.valorEntregue = valor_entregue_values[0] if valor_entregue_values else ""
        self.plataformasAfetadas = []

        # Resetar worklog
        self.registrarWorklog = False
        now = datetime.now()
        self.worklogInicio = now.strftime("%Y-%m-%d %H:%M:%S")
        self.worklogDuracao = 30
        self.worklogComment = ""

        # Resetar Epic parent
        self.epicParentKey = ""
        self.epicParentSummary = ""

    # Propriedades: Epic parent (opcionais)

    @Property(str, notify=epicParentKeyChanged)
    def epicParentKey(self) -> str:
        """Chave da issue Epic selecionada como parent (ex: PLATFORM-123)."""
        return self._epicParentKey

    @epicParentKey.setter
    def epicParentKey(self, value: str) -> None:
        if self._epicParentKey != value:
            self._epicParentKey = value
            self.epicParentKeyChanged.emit(value)

    @Property(str, notify=epicParentSummaryChanged)
    def epicParentSummary(self) -> str:
        """Resumo da Epic selecionada (para exibição na UI)."""
        return self._epicParentSummary

    @epicParentSummary.setter
    def epicParentSummary(self, value: str) -> None:
        if self._epicParentSummary != value:
            self._epicParentSummary = value
            self.epicParentSummaryChanged.emit(value)

    # Propriedade: valorEntregue
    @Property(str, notify=valorEntregueChanged)
    def valorEntregue(self) -> str:
        return self._valorEntregue

    @valorEntregue.setter
    def valorEntregue(self, value: str) -> None:
        if self._valorEntregue != value:
            self._valorEntregue = value or ""
            self.valorEntregueChanged.emit(self._valorEntregue)

    # Propriedade: plataformasAfetadas
    @Property(list, notify=plataformasAfetadasChanged)
    def plataformasAfetadas(self) -> List[str]:
        return self._plataformasAfetadas.copy() if self._plataformasAfetadas else []

    @plataformasAfetadas.setter
    def plataformasAfetadas(self, value: List[str]) -> None:
        if value is None:
            value = []
        if self._plataformasAfetadas != value:
            self._plataformasAfetadas = value.copy() if value else []
            self.plataformasAfetadasChanged.emit(self._plataformasAfetadas)

    # Propriedade: valorEntregueValues (read-only)
    @Property(list, notify=valorEntregueValuesChanged)
    def valorEntregueValues(self) -> List[str]:
        """Retorna lista de valores para Valor Entregue"""
        if self._config:
            return self._config.get_valor_entregue_values()
        return []

    # Propriedade: plataformasAfetadasValues (read-only)
    @Property(list, notify=plataformasAfetadasValuesChanged)
    def plataformasAfetadasValues(self) -> List[str]:
        """Retorna lista de valores para Plataformas afetadas"""
        if self._config:
            return self._config.get_plataformas_afetadas_values()
        return []
